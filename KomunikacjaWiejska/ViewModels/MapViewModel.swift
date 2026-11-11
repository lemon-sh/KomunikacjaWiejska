import CoreLocation
import Foundation
import MapKit
import Observation
import os
import SwiftUI

/// Observable MainActor view model coordinating SSE map streams, city selection, and detail sheets.

enum MapMode: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case satellite = "Satellite"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .explore:
            return String(localized: "mapMode.explore")
        case .satellite:
            return String(localized: "mapMode.satellite")
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .explore:
            return .standard(elevation: .realistic)
        case .satellite:
            return .hybrid(elevation: .realistic)
        }
    }
}

struct ActiveStopDetail: Equatable {
    var stop: Stop
    var departures: [StopDeparture] = []
    var isLoadingDepartures: Bool = true
    var errorMessage: String?
}

struct ActiveTripDetail: Equatable {
    let city: String
    let vehicleId: String?
    var tripId: String?
    var route: StopRoute?
    var headsign: String?
    var brigade: String?
    var tripInfo: TripInfo?
    var itinerary: Itinerary?
    var livePosition: VehiclePosition?
    var stopUpdates: [TripStopUpdate] = []
    var currentSequence: Int?
    var alerts: [TripAlert] = []
    var vehicleMetadata: VehicleMetadata?
    var isLoading: Bool = true
    var errorMessage: String?

    var displayRoute: StopRoute? {
        livePosition?.route ?? tripInfo?.route ?? route
    }

    var displayHeadsign: String {
        tripInfo?.headsign ?? headsign ?? displayRoute?.longName ?? ""
    }

    var displayBrigade: String? {
        livePosition?.brigade ?? tripInfo?.brigade ?? brigade
    }
}

@Observable
@MainActor
final class MapViewModel {
    struct CameraState: Equatable {
        var region: MKCoordinateRegion
        var distance: Double
        var heading: Double
        var pitch: Double
        var center: CLLocationCoordinate2D

        static func == (lhs: CameraState, rhs: CameraState) -> Bool {
            lhs.distance == rhs.distance
                && lhs.heading == rhs.heading
                && lhs.pitch == rhs.pitch
                && lhs.center.latitude == rhs.center.latitude
                && lhs.center.longitude == rhs.center.longitude
                && lhs.region.center.latitude == rhs.region.center.latitude
                && lhs.region.center.longitude == rhs.region.center.longitude
                && lhs.region.span.latitudeDelta == rhs.region.span.latitudeDelta
                && lhs.region.span.longitudeDelta == rhs.region.span.longitudeDelta
        }
    }

    enum FeatureSelection: Hashable, Sendable {
        case stop(String)
        case vehicle(String)
        case trip(city: String, tripId: String, initialRoute: StopRoute?, headsign: String?, brigade: String?)
    }

    enum LoadingPhase: Equatable {
        case idle
        case loading
        case failed(String, retryable: Bool)
    }

    // MARK: - Published UI State

    var cameraPosition: MapCameraPosition
    var selectedMapMode: MapMode = .explore
    var isTrackingUser: Bool = false
    var isFollowingVehicle: Bool = false

    var citiesCatalog: [City] = []
    var selectedCity: City?
    private(set) var selectedCityID: String
    var isShowingCityPicker: Bool = false
    var suggestedCity: City?

    var stops: [Stop] = []
    var vehicles: [VehiclePosition] = []
    var dots: [DotVehicle] = []

    var selection: FeatureSelection? {
        didSet {
            if selection != oldValue {
                handleSelectionChanged(from: oldValue, to: selection)
            }
        }
    }

    var activeStopDetail: ActiveStopDetail?
    var activeTripDetail: ActiveTripDetail?
    private(set) var canNavigateBackToStop: Bool = false

    var loadingPhase: LoadingPhase = .idle

    var isLoading: Bool {
        if case .loading = loadingPhase { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message, _) = loadingPhase { return message }
        return nil
    }

    var isRetryableError: Bool {
        if case .failed(_, let retryable) = loadingPhase { return retryable }
        return false
    }

    var cameraState: CameraState

    var currentDistance: Double {
        get { cameraState.distance }
        set { cameraState.distance = newValue }
    }

    var currentHeading: Double {
        get { cameraState.heading }
        set { cameraState.heading = newValue }
    }

    var visibleRegion: MKCoordinateRegion? {
        get { cameraState.region }
        set {
            if let region = newValue {
                cameraState.region = region
            }
        }
    }

    var currentCenter: CLLocationCoordinate2D {
        get { cameraState.center }
        set { cameraState.center = newValue }
    }

    var currentPitch: Double {
        get { cameraState.pitch }
        set { cameraState.pitch = newValue }
    }

    var isPitched3D: Bool {
        cameraState.pitch >= 5
    }

    var viewportWidthPoints: Double = MapConstants.defaultViewportWidthPoints

    /// Cities shown in `CityPickerSheet` (virtual meta-networks are hidden, matching webapp).
    var pickerCities: [City] {
        City.pickerCities(from: citiesCatalog)
    }

    // MARK: - Displayed Map Layers (Isolated During Stop/Trip Detail)

    var displayedStops: [Stop] {
        if let activeStopDetail {
            return [activeStopDetail.stop]
        }
        if activeTripDetail != nil {
            return []
        }
        return stops
    }

    var displayedVehicles: [VehiclePosition] {
        if let activeTripDetail {
            if let live = activeTripDetail.livePosition {
                return [live]
            }
            if let id = activeTripDetail.vehicleId,
               let cached = vehicles.first(where: { $0.id == id }) {
                return [cached]
            }
            return []
        }
        if let activeStopDetail {
            var unique: [String: VehiclePosition] = [:]
            for departure in activeStopDetail.departures {
                if let vehicle = departure.vehicle {
                    unique[vehicle.id] = vehicle
                }
            }
            return Array(unique.values).sorted { $0.id < $1.id }
        }
        return vehicles
    }

    var displayedDots: [DotVehicle] {
        guard activeStopDetail == nil, activeTripDetail == nil else {
            return []
        }
        return dots
    }

    var displayedStopEntrances: [StopEntrance] {
        activeStopDetail?.stop.entrances ?? []
    }

    var displayedItineraryStops: [ItineraryStop] {
        activeTripDetail?.itinerary?.stops ?? []
    }

    var displayedRouteCoordinates: [CLLocationCoordinate2D] {
        activeTripDetail?.itinerary?.coordinates ?? []
    }

    var displayedRouteColor: Color {
        activeTripDetail?.displayRoute?.displayColor ?? .accentColor
    }

    var areStopTitlesVisible: Bool {
        currentDistance <= 750
    }

    var selectedStopID: String? {
        if case .stop(let id) = selection { return id }
        return nil
    }

    var selectedVehicleID: String? {
        if case .vehicle(let id) = selection { return id }
        return activeTripDetail?.vehicleId
    }

    // MARK: - Internal State & Tasks

    private let transitDataProvider: TransitDataProviding
    private let persistence: CameraPersistenceStore
    private let debounceDuration: Duration
    private var hasExplicitCityOrCamera: Bool

    private var stopsByID: [String: Stop] = [:]
    private var vehiclesByID: [String: VehiclePosition] = [:]

    private var lastServerSuggestedCityID: String?
    private(set) var dismissedCityID: String?
    private var dismissedAtCenter: CLLocationCoordinate2D?

    private var stopReturnSelection: Stop?

    private var citiesLoadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var mapStreamTask: Task<Void, Never>?
    private var activeMapStreamKey: MapStreamKey?
    private var stopStreamTask: Task<Void, Never>?
    private var tripStreamTask: Task<Void, Never>?
    private var vehicleMetadataTask: Task<Void, Never>?
    private var backgroundDisconnectTask: Task<Void, Never>?

    private var lastMapMessageDate: Date?
    private var backgroundedAt: Date?

    private struct MapStreamKey: Equatable {
        let cityID: String
        let zoom: Double
        let bbox: BoundingBox
    }

    // MARK: - Initialization

    init(
        transitDataProvider: TransitDataProviding = ZbiorkomAPIClient(),
        persistence: CameraPersistenceStore = UserDefaultsCameraPersistenceStore(),
        debounceDuration: Duration = MapConstants.cameraDebounce
    ) {
        self.transitDataProvider = transitDataProvider
        self.persistence = persistence
        self.debounceDuration = debounceDuration

        let savedCityID = persistence.loadLastSelectedCityID()
        let savedCamera = persistence.loadSavedCamera()

        let initialCenter = savedCamera.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        } ?? CLLocationCoordinate2D(
            latitude: MapConstants.defaultCenterLatitude,
            longitude: MapConstants.defaultCenterLongitude
        )
        let initialDistance = savedCamera?.distance ?? MapConstants.defaultCityDistance

        self.selectedCityID = savedCityID ?? MapConstants.defaultCityID
        self.selectedCity = nil
        self.hasExplicitCityOrCamera = savedCamera != nil
        self.cameraPosition = .camera(
            MapCamera(
                centerCoordinate: initialCenter,
                distance: initialDistance,
                heading: 0,
                pitch: 0
            )
        )

        let span = MKCoordinateSpan(
            latitudeDelta: MapConstants.defaultCoordinateSpanDelta,
            longitudeDelta: MapConstants.defaultCoordinateSpanDelta
        )
        let initialRegion = MKCoordinateRegion(center: initialCenter, span: span)
        self.cameraState = CameraState(
            region: initialRegion,
            distance: initialDistance,
            heading: 0,
            pitch: 0,
            center: initialCenter
        )
    }

    isolated deinit {
        citiesLoadTask?.cancel()
        debounceTask?.cancel()
        mapStreamTask?.cancel()
        stopStreamTask?.cancel()
        tripStreamTask?.cancel()
        vehicleMetadataTask?.cancel()
        backgroundDisconnectTask?.cancel()
    }

    // MARK: - Lookup Helpers

    func city(for id: String) -> City? {
        City.city(id: id, in: citiesCatalog)
    }

    func timeZone(for cityID: String) -> TimeZone {
        city(for: cityID)?.timeZone
            ?? selectedCity?.timeZone
            ?? TimeZone(identifier: "Europe/Warsaw")
            ?? .current
    }

    func cachedStop(for id: String) -> Stop? {
        if let activeStopDetail, activeStopDetail.stop.id == id {
            return activeStopDetail.stop
        }
        return stopsByID[id]
    }

    func cachedVehicle(for id: String) -> VehiclePosition? {
        if let activeTripDetail, activeTripDetail.vehicleId == id, let live = activeTripDetail.livePosition {
            return live
        }
        return vehiclesByID[id]
    }

    // MARK: - Lifecycle & Map Stream Control

    func start() {
        if citiesCatalog.isEmpty {
            loadCitiesCatalogIfNeeded()
        } else {
            startMapStreamForCurrentViewport()
        }
    }

    func retry() {
        if citiesCatalog.isEmpty {
            loadCitiesCatalogIfNeeded(forceReload: true)
        } else {
            startMapStreamForCurrentViewport(forceRestart: true)
        }
    }

    func loadCitiesCatalogIfNeeded(forceReload: Bool = false) {
        if forceReload {
            citiesLoadTask?.cancel()
            citiesLoadTask = nil
        }
        guard citiesLoadTask == nil else { return }

        if citiesCatalog.isEmpty {
            loadingPhase = .loading
        }

        citiesLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await transitDataProvider.fetchCities()
                guard !Task.isCancelled else { return }
                guard !fetched.isEmpty else {
                    self.citiesLoadTask = nil
                    self.loadingPhase = .failed(String(localized: "error.invalidResponse"), retryable: true)
                    return
                }

                self.citiesCatalog = fetched
                self.citiesLoadTask = nil

                if let resolved = City.city(id: self.selectedCityID, in: fetched)
                    ?? (self.hasExplicitCityOrCamera ? self.selectedCity : nil)
                    ?? City.city(id: MapConstants.defaultCityID, in: fetched)
                    ?? fetched.first(where: { !$0.isVirtual })
                    ?? fetched.first {
                    let shouldReposition = !self.hasExplicitCityOrCamera && (
                        abs(resolved.latitude - self.cameraState.center.latitude) > 0.001
                            || abs(resolved.longitude - self.cameraState.center.longitude) > 0.001
                    )
                    self.selectedCity = resolved
                    self.selectedCityID = resolved.id
                    self.persistence.saveLastSelectedCityID(resolved.id)
                    if shouldReposition {
                        self.applyCameraState(
                            CameraState(
                                region: MKCoordinateRegion(
                                    center: resolved.coordinate,
                                    span: MKCoordinateSpan(
                                        latitudeDelta: resolved.defaultLatitudeDelta,
                                        longitudeDelta: resolved.defaultLongitudeDelta
                                    )
                                ),
                                distance: MapConstants.defaultCityDistance,
                                heading: 0,
                                pitch: 0,
                                center: resolved.coordinate
                            ),
                            animated: false
                        )
                    }
                }

                self.startMapStreamForCurrentViewport(forceRestart: true)
            } catch is CancellationError {
                return
            } catch {
                self.citiesLoadTask = nil
                let message = error.localizedDescription.isEmpty
                    ? String(localized: "error.invalidResponse")
                    : error.localizedDescription
                self.loadingPhase = .failed(message, retryable: true)
                Logger.catalog.error("Failed to load /api6 city catalog: \(message, privacy: .public)")
            }
        }
    }

    func pauseForBackground() {
        debounceTask?.cancel()
        debounceTask = nil
        backgroundedAt = Date()

        backgroundDisconnectTask?.cancel()
        backgroundDisconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: MapConstants.sseBackgroundDisconnectDelay)
            } catch {
                return
            }
            guard let self, self.backgroundedAt != nil else { return }
            self.cancelAllStreams()
        }
    }

    func resumeFromBackground() {
        backgroundDisconnectTask?.cancel()
        backgroundDisconnectTask = nil

        if citiesCatalog.isEmpty {
            loadCitiesCatalogIfNeeded()
            return
        }

        let wasBackgroundedLong = backgroundedAt.map {
            Date().timeIntervalSince($0) >= MapConstants.sseForegroundStaleInterval
        } ?? true
        let isStreamStale = lastMapMessageDate.map {
            Date().timeIntervalSince($0) >= MapConstants.sseForegroundStaleInterval
        } ?? true
        backgroundedAt = nil

        if mapStreamTask == nil || wasBackgroundedLong || isStreamStale {
            startMapStreamForCurrentViewport(forceRestart: true)
            restartActiveDetailStreamIfNeeded()
        }
    }

    func startMapStreamForCurrentViewport(forceRestart: Bool = false) {
        guard !citiesCatalog.isEmpty || selectedCity != nil else { return }
        guard let bbox = BoundingBox(cameraState.region)?.clamped else { return }
        let zoom = bbox.webMercatorZoom(viewportWidth: viewportWidthPoints)
        let cityID = selectedCityID
        let key = MapStreamKey(cityID: cityID, zoom: zoom, bbox: bbox)

        if !forceRestart, activeMapStreamKey == key, mapStreamTask != nil {
            return
        }

        cancelMapStream()
        activeMapStreamKey = key

        if stops.isEmpty && vehicles.isEmpty && dots.isEmpty {
            loadingPhase = .loading
        }

        let stream = transitDataProvider.streamMapFeatures(city: cityID, zoom: zoom, bbox: bbox)

        mapStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled,
                          self.selectedCityID == cityID,
                          self.activeMapStreamKey == key else {
                        return
                    }
                    self.handleMapFeaturesEvent(event)
                }
                if self.selectedCityID == cityID && self.activeMapStreamKey == key {
                    self.mapStreamTask = nil
                    if case .loading = self.loadingPhase {
                        self.loadingPhase = .idle
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedCityID == cityID, self.activeMapStreamKey == key else { return }
                self.mapStreamTask = nil
                let message = error.localizedDescription.isEmpty
                    ? String(localized: "error.invalidResponse")
                    : error.localizedDescription
                self.loadingPhase = .failed(message, retryable: true)
                Logger.api.error("mapFeatures stream error for \(cityID, privacy: .public): \(message, privacy: .public)")
            }
        }
    }

    private func handleMapFeaturesEvent(_ event: MapFeaturesEvent) {
        switch event {
        case .initial(let payload):
            var newStopsByID: [String: Stop] = [:]
            newStopsByID.reserveCapacity(payload.stops.count)
            for stop in payload.stops {
                newStopsByID[stop.id] = stop
            }
            stopsByID = newStopsByID
            stops = payload.stops
            lastServerSuggestedCityID = payload.suggestedCity
            loadingPhase = .idle
            updateRegionSuggestion()

        case .message(let payload):
            var newVehiclesByID: [String: VehiclePosition] = [:]
            newVehiclesByID.reserveCapacity(payload.positions.count)
            for vehicle in payload.positions {
                newVehiclesByID[vehicle.id] = vehicle
            }
            vehiclesByID = newVehiclesByID
            vehicles = payload.positions
            dots = payload.dots
            lastMapMessageDate = Date()
            loadingPhase = .idle
        }
    }

    private func cancelMapStream() {
        mapStreamTask?.cancel()
        mapStreamTask = nil
        activeMapStreamKey = nil
    }

    private func cancelAllStreams() {
        cancelMapStream()
        stopStreamTask?.cancel()
        stopStreamTask = nil
        tripStreamTask?.cancel()
        tripStreamTask = nil
        vehicleMetadataTask?.cancel()
        vehicleMetadataTask = nil
    }

    // MARK: - City Selection & Camera Handling

    func selectCity(_ city: City, repositionCamera: Bool = true) {
        let cityChanged = selectedCityID != city.id
        selectedCity = city
        selectedCityID = city.id
        hasExplicitCityOrCamera = true
        persistence.saveLastSelectedCityID(city.id)
        isShowingCityPicker = false

        if cityChanged {
            selection = nil
            stopReturnSelection = nil
            canNavigateBackToStop = false
            activeStopDetail = nil
            activeTripDetail = nil
            stops = []
            stopsByID.removeAll()
            vehicles = []
            vehiclesByID.removeAll()
            dots = []
            lastServerSuggestedCityID = nil
            suggestedCity = nil
            dismissedCityID = nil
            dismissedAtCenter = nil
            loadingPhase = .idle
            cancelAllStreams()
        }

        if repositionCamera {
            let center = city.coordinate
            let distance = MapConstants.defaultCityDistance
            let span = MKCoordinateSpan(
                latitudeDelta: city.defaultLatitudeDelta,
                longitudeDelta: city.defaultLongitudeDelta
            )
            applyCameraState(
                CameraState(
                    region: MKCoordinateRegion(center: center, span: span),
                    distance: distance,
                    heading: 0,
                    pitch: 0,
                    center: center
                ),
                animated: true
            )
        }

        if cityChanged {
            startMapStreamForCurrentViewport(forceRestart: true)
        }
    }

    func switchToSuggestedCity() {
        guard let target = suggestedCity else { return }
        suggestedCity = nil
        dismissedCityID = nil
        dismissedAtCenter = nil
        selectCity(target, repositionCamera: false)
        startMapStreamForCurrentViewport(forceRestart: true)
    }

    func dismissSuggestedCity() {
        dismissedCityID = suggestedCity?.id
        dismissedAtCenter = cameraState.center
        suggestedCity = nil
    }

    func toggleMapMode() {
        selectedMapMode = (selectedMapMode == .explore) ? .satellite : .explore
    }

    func centerOnUserLocation(coordinate: CLLocationCoordinate2D) {
        isTrackingUser = true
        isFollowingVehicle = false
        let distance = MapConstants.userFocusDistance
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: distance,
            longitudinalMeters: distance
        )
        applyCameraState(
            CameraState(
                region: region,
                distance: distance,
                heading: currentHeading,
                pitch: currentPitch,
                center: coordinate
            ),
            animated: true
        )
    }

    func toggleFollowVehicle() {
        isFollowingVehicle.toggle()
        if isFollowingVehicle, let coord = activeTripDetail?.livePosition?.coordinate {
            focusCameraOnVehicle(coordinate: coord)
        }
    }

    func resetPitchTo2D() {
        applyCameraState(
            CameraState(
                region: cameraState.region,
                distance: cameraState.distance,
                heading: cameraState.heading,
                pitch: 0,
                center: cameraState.center
            ),
            animated: true
        )
    }

    func setCameraPositionFromGesture(_ newPosition: MapCameraPosition) {
        isTrackingUser = false
        isFollowingVehicle = false
        cameraPosition = newPosition
    }

    func applyCameraState(_ state: CameraState, animated: Bool) {
        cameraState = state
        let mapCamera = MapCamera(
            centerCoordinate: state.center,
            distance: state.distance,
            heading: state.heading,
            pitch: state.pitch
        )
        if animated {
            withAnimation {
                cameraPosition = .camera(mapCamera)
            }
        } else {
            cameraPosition = .camera(mapCamera)
        }
    }

    func handleCameraChange(to context: MapCameraUpdateContext) {
        let newState = CameraState(
            region: context.region,
            distance: context.camera.distance,
            heading: context.camera.heading,
            pitch: context.camera.pitch,
            center: context.camera.centerCoordinate
        )
        cameraState = newState
        updateRegionSuggestion()

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.debounceDuration ?? MapConstants.cameraDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.startMapStreamForCurrentViewport()
        }
    }

    func saveCameraPosition() {
        persistence.saveLastSelectedCityID(selectedCityID)
        persistence.saveCamera(
            latitude: cameraState.center.latitude,
            longitude: cameraState.center.longitude,
            distance: cameraState.distance
        )
    }

    // MARK: - City Suggestion

    func updateRegionSuggestion() {
        if let dismissedCenter = dismissedAtCenter,
           Self.distanceMeters(from: cameraState.center, to: dismissedCenter) > MapConstants.dismissalResetDistanceMeters {
            lastServerSuggestedCityID = nil
            dismissedCityID = nil
            dismissedAtCenter = nil
        }

        // 1. Prefer server-emitted `suggestedCity` from mapFeatures `initial`.
        if let serverCityID = lastServerSuggestedCityID,
           serverCityID != selectedCityID,
           serverCityID != dismissedCityID,
           let target = City.city(id: serverCityID, in: citiesCatalog),
           !target.isVirtual {
            suggestedCity = target
            return
        }

        // 2. Local nearest non-virtual city lookup from `/api6` catalog when panned outside current city's coverage.
        guard let currentCity = selectedCity else {
            suggestedCity = nil
            return
        }
        suggestedCity = Self.nearestSuggestedCity(
            for: cameraState.center,
            currentCity: currentCity,
            dismissedCityID: dismissedCityID,
            allCities: citiesCatalog
        )
    }

    static func nearestSuggestedCity(
        for center: CLLocationCoordinate2D,
        currentCity: City,
        dismissedCityID: String?,
        allCities: [City]
    ) -> City? {
        if !currentCity.isVirtual && currentCity.coverageRadiusMeters > 0 {
            if Self.distanceMeters(from: center, to: currentCity.coordinate) <= currentCity.coverageRadiusMeters {
                return nil
            }
        }

        var nearest: (city: City, distance: Double)?
        for candidate in allCities where !candidate.isVirtual && candidate.id != currentCity.id {
            let distance = Self.distanceMeters(from: center, to: candidate.coordinate)
            guard distance <= candidate.coverageRadiusMeters else { continue }
            if let currentBest = nearest {
                if distance < currentBest.distance {
                    nearest = (candidate, distance)
                }
            } else {
                nearest = (candidate, distance)
            }
        }

        guard let match = nearest?.city, match.id != dismissedCityID else {
            return nil
        }
        return match
    }

    private static func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    // MARK: - Selection, Departures & Trip Navigation

    func openDeparture(_ departure: StopDeparture) {
        if let activeStopDetail {
            stopReturnSelection = activeStopDetail.stop
            canNavigateBackToStop = true
        }
        isFollowingVehicle = false

        if let vehicle = departure.vehicle {
            selection = .vehicle(vehicle.id)
        } else {
            selection = .trip(
                city: departure.trip.city,
                tripId: departure.trip.id,
                initialRoute: departure.trip.route,
                headsign: departure.trip.headsign,
                brigade: departure.trip.brigade
            )
        }
    }

    func navigateBackToStop() {
        guard let stop = stopReturnSelection else {
            selection = nil
            return
        }
        stopReturnSelection = nil
        canNavigateBackToStop = false
        stopsByID[stop.id] = stop
        selection = .stop(stop.id)
    }

    private func handleSelectionChanged(from oldValue: FeatureSelection?, to newValue: FeatureSelection?) {
        stopStreamTask?.cancel()
        stopStreamTask = nil
        tripStreamTask?.cancel()
        tripStreamTask = nil
        vehicleMetadataTask?.cancel()
        vehicleMetadataTask = nil

        let previousStopDetail = activeStopDetail
        guard let newValue else {
            activeStopDetail = nil
            activeTripDetail = nil
            stopReturnSelection = nil
            canNavigateBackToStop = false
            isFollowingVehicle = false
            return
        }

        switch newValue {
        case .stop(let stopID):
            activeTripDetail = nil
            stopReturnSelection = nil
            canNavigateBackToStop = false
            isFollowingVehicle = false
            let initialStop = stopsByID[stopID]
            guard let stop = initialStop else {
                activeStopDetail = nil
                return
            }
            activeStopDetail = ActiveStopDetail(stop: stop, departures: [], isLoadingDepartures: true)
            startStopStream(stop: stop)

        case .vehicle(let vehicleID):
            activeStopDetail = nil
            let cached = vehiclesByID[vehicleID]
                ?? previousStopDetail?.departures.compactMap(\.vehicle).first(where: { $0.id == vehicleID })
            let cityID = cached?.city ?? selectedCityID
            activeTripDetail = ActiveTripDetail(
                city: cityID,
                vehicleId: vehicleID,
                tripId: cached?.tripId,
                route: cached?.route,
                headsign: cached?.routeLongName,
                brigade: cached?.brigade,
                livePosition: cached,
                isLoading: true
            )
            startVehicleTripStream(city: cityID, vehicleId: vehicleID)
            fetchMetadataForVehicle(city: cityID, vehicleId: vehicleID)

        case let .trip(city, tripId, initialRoute, headsign, brigade):
            activeStopDetail = nil
            activeTripDetail = ActiveTripDetail(
                city: city,
                vehicleId: nil,
                tripId: tripId,
                route: initialRoute,
                headsign: headsign,
                brigade: brigade,
                isLoading: true
            )
            startTripStream(city: city, tripId: tripId)
        }
    }

    private func restartActiveDetailStreamIfNeeded() {
        switch selection {
        case .stop:
            if let stop = activeStopDetail?.stop {
                startStopStream(stop: stop)
            }
        case .vehicle(let vehicleID):
            let cityID = activeTripDetail?.city ?? selectedCityID
            startVehicleTripStream(city: cityID, vehicleId: vehicleID)
        case let .trip(city, tripId, _, _, _):
            startTripStream(city: city, tripId: tripId)
        case nil:
            break
        }
    }

    private func startStopStream(stop: Stop) {
        stopStreamTask?.cancel()
        let targetStopID = stop.id
        let targetCityID = stop.city
        let stream = transitDataProvider.streamStopDepartures(
            city: targetCityID,
            stopId: targetStopID,
            limit: MapConstants.defaultStopDeparturesLimit
        )

        stopStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled, self.selectedStopID == targetStopID else { return }
                    switch event {
                    case .initial(let fullStop):
                        self.stopsByID[fullStop.id] = fullStop
                        if var detail = self.activeStopDetail, detail.stop.id == fullStop.id {
                            detail.stop = fullStop
                            detail.errorMessage = nil
                            self.activeStopDetail = detail
                        }
                    case .message(let departures):
                        if var detail = self.activeStopDetail, detail.stop.id == targetStopID {
                            detail.departures = departures
                            detail.isLoadingDepartures = false
                            detail.errorMessage = nil
                            self.activeStopDetail = detail
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.selectedStopID == targetStopID else { return }
                if var detail = self.activeStopDetail {
                    detail.isLoadingDepartures = false
                    detail.errorMessage = error.localizedDescription
                    self.activeStopDetail = detail
                }
            }
        }
    }

    private func startVehicleTripStream(city: String, vehicleId: String) {
        let stream = transitDataProvider.streamVehiclePosition(city: city, vehicleId: vehicleId)
        consumeTripStream(stream)
    }

    private func startTripStream(city: String, tripId: String) {
        let stream = transitDataProvider.streamTrip(city: city, tripId: tripId)
        consumeTripStream(stream)
    }

    private func consumeTripStream(_ stream: AsyncThrowingStream<TripStreamEvent, Error>) {
        tripStreamTask?.cancel()
        tripStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    guard !Task.isCancelled, var detail = self.activeTripDetail else { return }
                    switch event {
                    case .initial(let initial):
                        detail.tripInfo = initial.trip
                        detail.tripId = initial.trip.id
                        detail.itinerary = initial.itinerary
                        detail.route = initial.trip.route
                        detail.headsign = initial.trip.headsign
                        detail.brigade = initial.trip.brigade
                        detail.isLoading = false
                        detail.errorMessage = nil
                        self.activeTripDetail = detail

                    case .message(let update):
                        detail.livePosition = update.position ?? detail.livePosition
                        if !update.stops.isEmpty {
                            detail.stopUpdates = update.stops
                        }
                        if let sequence = update.sequence {
                            detail.currentSequence = sequence
                        }
                        if let alerts = update.alerts {
                            detail.alerts = alerts
                        }
                        detail.isLoading = false
                        detail.errorMessage = nil
                        self.activeTripDetail = detail

                        if let pos = update.position {
                            self.vehiclesByID[pos.id] = pos
                            if self.isFollowingVehicle {
                                self.focusCameraOnVehicle(coordinate: pos.coordinate)
                            }
                        }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard var detail = self.activeTripDetail else { return }
                detail.isLoading = false
                detail.errorMessage = error.localizedDescription
                self.activeTripDetail = detail
            }
        }
    }

    private func fetchMetadataForVehicle(city: String, vehicleId: String) {
        vehicleMetadataTask?.cancel()
        vehicleMetadataTask = Task { [weak self] in
            guard let self else { return }
            do {
                let metadata = try await transitDataProvider.fetchVehicleMetadata(city: city, vehicleId: vehicleId)
                guard !Task.isCancelled, var detail = self.activeTripDetail, detail.vehicleId == vehicleId else {
                    return
                }
                detail.vehicleMetadata = metadata
                self.activeTripDetail = detail
            } catch {
                // Vehicle fleet metadata is optional enhancement (404 for unknown/virtual fleet).
                return
            }
        }
    }

    private func focusCameraOnVehicle(coordinate: CLLocationCoordinate2D) {
        applyCameraState(
            CameraState(
                region: MKCoordinateRegion(
                    center: coordinate,
                    span: cameraState.region.span
                ),
                distance: min(cameraState.distance, MapConstants.userFocusDistance),
                heading: currentHeading,
                pitch: currentPitch,
                center: coordinate
            ),
            animated: true
        )
    }
}
