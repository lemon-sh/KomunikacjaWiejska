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
    public var selectedMapMode: MapMode = .explore
    public var isShowingMapModes: Bool = false
    public var isTrackingUser: Bool = false

    /// Whether the currently selected city has a request in flight.
    public var isLoading: Bool {
        if case .loading(let cityID) = loadState, cityID == selectedCity.id {
            return true
        }
        return false
    }

    /// Failure message for the currently selected city, if any. Errors are
    /// tracked per city so a failed fetch for city A never surfaces while
    /// viewing city B.
    public var errorMessage: String? {
        errorsByCity[selectedCity.id]
    }

    /// Cycle a city's stop fetch can be in. Guarantees one in-flight request
    /// per city and makes `loadStopsForSelectedCity()` idempotent.
    private enum LoadState: Equatable {
        case idle
        case loading(cityID: String)
        case loaded(cityID: String)
        case failed(cityID: String)
    }

    private var loadState: LoadState = .idle

    /// Camera distance (in metres) above which stops are displayed as smaller
    /// compact points. Distance-based so it is independent of each city's
    /// default span: every normal city (span ≤ 0.15°) loads fully zoomed
    /// markers, while the countrywide PKP view starts compact.
    public let compactDisplayDistanceThreshold: Double = 50_000

    /// Whether the camera is far enough that stops should be displayed as smaller points.
    public var isCompactDisplayMode: Bool {
        return currentDistance > compactDisplayDistanceThreshold
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
    private var errorsByCity: [String: String] = [:]
    /// Generation token guarding against stale responses: each fetch gets a
    /// fresh token, and a response only applies if it still matches.
    private var requestGeneration = UUID()

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
            // Cancel any request still in flight for the previous city so it
            // cannot overwrite this cache hit.
            activeFetchTask?.cancel()
            requestGeneration = UUID()
            stops = cachedStops
            errorsByCity[city.id] = nil
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
        requestGeneration = UUID()
        let generation = requestGeneration
        errorsByCity[city.id] = nil
        loadState = .loading(cityID: city.id)
        // The previous city's stops must not linger on screen while the new
        // city's request is in flight.
        stops = []

        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let fetchedStops = try await self.apiClient.fetchStops(city: city.id, bbox: nil)
                guard !Task.isCancelled, generation == self.requestGeneration else { return }
                self.stopsCache[city.id] = fetchedStops
                if self.selectedCity.id == city.id {
                    self.stops = fetchedStops
                    self.loadState = .loaded(cityID: city.id)
                }
            } catch {
                guard !Task.isCancelled, generation == self.requestGeneration else { return }
                if self.selectedCity.id == city.id {
                    self.errorsByCity[city.id] = error.localizedDescription
                    self.loadState = .failed(cityID: city.id)
                }
            }
        }
    }
}
