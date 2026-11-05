import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

/// Available map rendering modes.
public enum MapMode: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case satellite = "Satellite"

    public var id: String { rawValue }

    public var mapStyle: MapStyle {
        switch self {
        case .explore:
            return .standard(pointsOfInterest: .excludingAll, showsTraffic: true)
        case .satellite:
            return .hybrid(elevation: .realistic, showsTraffic: true)
        }
    }
}

@Observable
@MainActor
public final class MapViewModel {
    public var selectedCity: City {
        didSet {
            guard selectedCity != oldValue else { return }
            UserDefaults.standard.set(selectedCity.id, forKey: "lastSelectedCityId")
            selectedStop = nil
            repositionCameraForCurrentCity()
            loadStopsForSelectedCity()
        }
    }

    public var cameraPosition: MapCameraPosition
    public var visibleRegion: MKCoordinateRegion?
    public var currentHeading: Double = 0
    public var currentPitch: Double = 0
    public var currentDistance: Double = 15000
    public var currentCenter: CLLocationCoordinate2D
    public var stops: [Stop] = []
    public var selectedStop: Stop?
    public var isShowingCityPicker: Bool = false
    public var isLoading: Bool = false
    public var errorMessage: String?

    public var selectedMapMode: MapMode = .explore
    public var isShowingMapModes: Bool = false
    public var isTrackingUser: Bool = false

    /// Cycle a city's stop fetch can be in. Guarantees one in-flight request
    /// per city and makes `loadStopsForSelectedCity()` idempotent.
    private enum LoadState: Equatable {
        case idle
        case loading(cityID: String)
        case loaded(cityID: String)
        case failed(cityID: String)
    }

    private var loadState: LoadState = .idle

    /// Threshold coordinate span delta above which stops are displayed as smaller compact points.
    public let compactDisplayThreshold: Double = 0.05

    /// Whether the map is zoomed out far enough that stops should be displayed as smaller points.
    public var isCompactDisplayMode: Bool {
        guard let region = visibleRegion else { return false }
        return region.span.latitudeDelta > compactDisplayThreshold
    }

    /// Threshold above which we do not fetch/display stops to avoid lag and overloading the map.
    public let maxSpanForStops: Double = 0.09

    public var isZoomedOutForStops: Bool {
        return false
    }

    /// Whether the map is currently pitched in 3D (pitch > 1.0 degree)
    public var isPitched3D: Bool {
        return currentPitch > 1.0
    }

    private let apiClient: any StopsProviding
    // `nonisolated(unsafe)`: only mutated from `@MainActor` methods, read from
    // `deinit` (nonisolated by definition). `Task` is `Sendable`, so cancelling
    // from any context is safe; the reference itself is never read concurrently.
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    private var stopsCache: [String: [Stop]] = [:]

    public init(
        apiClient: any StopsProviding = ZbiorkomAPIClient.shared,
        initialCity: City? = nil
    ) {
        self.apiClient = apiClient

        let chosenCity: City
        if let initialCity = initialCity {
            chosenCity = initialCity
        } else if let savedId = UserDefaults.standard.string(forKey: "lastSelectedCityId"),
                  let found = City.allCities.first(where: { $0.id == savedId }) {
            chosenCity = found
        } else {
            chosenCity = .warsaw
        }

        self.selectedCity = chosenCity
        let initialRegion = MKCoordinateRegion(
            center: chosenCity.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: chosenCity.defaultLatitudeDelta,
                longitudeDelta: chosenCity.defaultLongitudeDelta
            )
        )
        self.visibleRegion = initialRegion
        self.currentCenter = chosenCity.coordinate
        self.cameraPosition = .region(initialRegion)
    }

    deinit {
        activeFetchTask?.cancel()
    }

    public func repositionCameraForCurrentCity() {
        let newRegion = MKCoordinateRegion(
            center: selectedCity.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: selectedCity.defaultLatitudeDelta,
                longitudeDelta: selectedCity.defaultLongitudeDelta
            )
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            cameraPosition = .region(newRegion)
        }
        visibleRegion = newRegion
        currentCenter = selectedCity.coordinate
        currentHeading = 0
        currentPitch = 0
        isTrackingUser = false
    }

    public func handleCameraChange(to context: MapCameraUpdateContext) {
        visibleRegion = context.region
        currentHeading = context.camera.heading
        currentPitch = context.camera.pitch
        currentDistance = context.camera.distance
        currentCenter = context.camera.centerCoordinate

        if isTrackingUser, let userLocation = LocationManager.shared.userLocation {
            let cameraLoc = CLLocation(
                latitude: context.camera.centerCoordinate.latitude,
                longitude: context.camera.centerCoordinate.longitude
            )
            if cameraLoc.distance(from: userLocation) > 150 {
                isTrackingUser = false
            }
        }
    }

    /// Centers the map camera on the user's coordinate with a smooth spring animation.
    public func centerOnUserLocation(coordinate: CLLocationCoordinate2D?) {
        guard let coordinate = coordinate else { return }
        isTrackingUser = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            let camera = MapCamera(
                centerCoordinate: coordinate,
                distance: min(currentDistance, 4000),
                heading: currentHeading,
                pitch: currentPitch
            )
            cameraPosition = .camera(camera)
            currentCenter = coordinate
        }
    }

    /// Flattens the map view to 2D (pitch = 0) while keeping current center, distance, and heading intact.
    public func resetPitchTo2D() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            let camera = MapCamera(
                centerCoordinate: currentCenter,
                distance: currentDistance,
                heading: currentHeading,
                pitch: 0
            )
            cameraPosition = .camera(camera)
            currentPitch = 0
        }
    }

    /// Loads stops for the selected city. Idempotent while a request for the
    /// same city is already in flight or already loaded; a manual refresh can
    /// force a refetch via `refreshStopsForSelectedCity()`.
    public func loadStopsForSelectedCity() {
        let city = selectedCity

        switch loadState {
        case .loading(let id), .loaded(let id):
            guard id != city.id else { return }
        case .idle, .failed:
            break
        }

        // If stops for this city are already in memory, display them immediately and do not fetch
        if let cachedStops = stopsCache[city.id] {
            stops = cachedStops
            isLoading = false
            errorMessage = nil
            loadState = .loaded(cityID: city.id)
            return
        }

        fetchStops(for: city)
    }

    /// Forces a fresh fetch for the selected city, discarding any cached data.
    public func refreshStopsForSelectedCity() {
        stopsCache.removeValue(forKey: selectedCity.id)
        loadState = .idle
        loadStopsForSelectedCity()
    }

    private func fetchStops(for city: City) {
        activeFetchTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadState = .loading(cityID: city.id)

        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let fetchedStops = try await self.apiClient.fetchStops(city: city.id, bbox: nil)
                guard !Task.isCancelled else { return }
                self.stopsCache[city.id] = fetchedStops
                if self.selectedCity.id == city.id {
                    self.stops = fetchedStops
                    self.isLoading = false
                    self.loadState = .loaded(cityID: city.id)
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.selectedCity.id == city.id {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.loadState = .failed(cityID: city.id)
                }
            }
        }
    }

    public func selectStop(_ stop: Stop?) {
        selectedStop = stop
    }
}
