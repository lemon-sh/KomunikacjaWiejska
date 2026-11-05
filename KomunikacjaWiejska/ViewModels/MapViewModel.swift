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
            return .standard(pointsOfInterest: .excludingAll)
        case .satellite:
            return .hybrid(elevation: .realistic)
        }
    }
}

@Observable
@MainActor
public final class MapViewModel {
    public var selectedCity: City {
        didSet {
            UserDefaults.standard.set(selectedCity.id, forKey: "lastSelectedCityId")
            repositionCameraForCurrentCity()
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

    /// Threshold above which we do not fetch/display stops to avoid lag and overloading the map.
    public let maxSpanForStops: Double = 0.09

    public var isZoomedOutForStops: Bool {
        guard let region = visibleRegion else { return false }
        return region.span.latitudeDelta > maxSpanForStops
    }

    /// Whether the map is currently pitched in 3D (pitch > 1.0 degree)
    public var isPitched3D: Bool {
        return currentPitch > 1.0
    }

    private let apiClient: ZbiorkomAPIClient
    private var activeFetchTask: Task<Void, Never>?

    public init(
        apiClient: ZbiorkomAPIClient = .shared,
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
        refreshStops()
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

        refreshStops()
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
        refreshStops()
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

    public func refreshStops() {
        guard let region = visibleRegion else { return }

        // If zoomed out too far, clear stops so user gets clear hint to zoom in
        if isZoomedOutForStops {
            activeFetchTask?.cancel()
            stops = []
            return
        }

        guard let bbox = BoundingBox(region: region) else { return }

        activeFetchTask?.cancel()
        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
            self.errorMessage = nil

            do {
                let fetchedStops = try await self.apiClient.fetchStops(
                    city: self.selectedCity.id,
                    bbox: bbox
                )
                if !Task.isCancelled {
                    self.stops = fetchedStops
                    self.isLoading = false
                }
            } catch {
                if !Task.isCancelled {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func selectStop(_ stop: Stop?) {
        selectedStop = stop
    }
}
