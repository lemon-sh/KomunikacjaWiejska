import CoreLocation
import Foundation
import MapKit
import Observation
import os
import SwiftUI

extension CLLocationCoordinate2D {
    /// Structure equality with a small epsilon, used for camera-state change
    /// detection. MapKit reports identical values with float jitter.
    func isApproximatelyEqual(to other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 1e-7 && abs(longitude - other.longitude) < 1e-7
    }

    /// Great-circle distance in metres to another coordinate.
    nonisolated func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// Available map rendering modes.
enum MapMode: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case satellite = "Satellite"

    var id: String { rawValue }

    /// Localized label. `rawValue` stays a stable, locale-independent
    /// identifier (persisted state, tests, analytics); never render it.
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
            return .standard(pointsOfInterest: .excludingAll, showsTraffic: true)
        case .satellite:
            return .hybrid(elevation: .realistic, showsTraffic: true)
        }
    }
}

/// Why the map is currently loading. Lets the UI distinguish a cold start
/// from a same-city viewport load or a city switch without inferring it from
/// timing.
enum StopLoadingPhase: Equatable, Sendable {
    case initial
    case refresh
    case citySwitch
}

@Observable
@MainActor
final class MapViewModel {
    /// Camera-derived metrics grouped into one tracked value so a camera
    /// gesture updates a single observation instead of four.
    /// `center` is derived from `region.center` so they can never diverge.
    struct CameraState: Equatable, Sendable {
        var region: MKCoordinateRegion
        var heading: Double
        var pitch: Double
        var distance: Double

        var center: CLLocationCoordinate2D {
            get { region.center }
            set { region.center = newValue }
        }

        init(
            region: MKCoordinateRegion,
            heading: Double = 0,
            pitch: Double = 0,
            distance: Double = 0,
            center: CLLocationCoordinate2D? = nil
        ) {
            self.region = (center != nil) ? MKCoordinateRegion(center: center!, span: region.span) : region
            self.heading = heading
            self.pitch = pitch
            self.distance = distance
        }

        static func == (lhs: CameraState, rhs: CameraState) -> Bool {
            lhs.heading == rhs.heading
                && lhs.pitch == rhs.pitch
                && lhs.distance == rhs.distance
                && lhs.center.isApproximatelyEqual(to: rhs.center)
                && abs(lhs.region.span.latitudeDelta - rhs.region.span.latitudeDelta) < 1e-7
                && abs(lhs.region.span.longitudeDelta - rhs.region.span.longitudeDelta) < 1e-7
        }
    }

    private(set) var selectedCity: City

    /// City suggested to the user when viewing an area outside the current city's territory.
    private(set) var suggestedCity: City?
    /// City ID whose suggestion was dismissed by the user to avoid repeated prompting.
    private(set) var dismissedCityID: String?

    @ObservationIgnored private var _cameraPosition: MapCameraPosition
    @ObservationIgnored private var _cameraState: CameraState

    var cameraPosition: MapCameraPosition {
        get {
            access(keyPath: \.cameraPosition)
            return _cameraPosition
        }
        set {
            withMutation(keyPath: \.cameraPosition) {
                _cameraPosition = newValue
            }
        }
    }

    /// Updates internal camera position from MapKit user gestures without triggering
    /// SwiftUI Observation invalidations. User panning is already rendered smoothly by MapKit/Metal;
    /// re-evaluating the SwiftUI Map and annotation tree on every pan tick causes 30–56ms main thread hitches.
    func setCameraPositionFromGesture(_ newPosition: MapCameraPosition) {
        _cameraPosition = newPosition
        isTrackingVehicle = false
    }

    var cameraState: CameraState {
        get { _cameraState }
        set {
            _cameraState = newValue
            syncDerivedCameraProperties(from: newValue)
        }
    }

    /// Markers currently rendered on the map.
    private(set) var stops: [Stop] = []
    var isShowingCityPicker: Bool = false
    var selectedMapMode: MapMode = .explore
    var isTrackingUser: Bool = false

    /// Real-time live vehicles currently rendered on the map.
    private(set) var vehicles: [VehiclePosition] = []
    private(set) var isTrackingVehicle: Bool = false
    private(set) var isVehiclesVisible: Bool = true
    private(set) var isVehicleCompactDisplayMode: Bool = true
    private(set) var isRetryableError: Bool = true

    enum FeatureSelection: Hashable, Sendable {
        case stop(String)
        case vehicle(String)
    }

    /// Active map selection (single source of truth shared with `Map(selection:)`).
    var selection: FeatureSelection? {
        didSet {
            switch selection {
            case .vehicle(let id):
                isTrackingVehicle = true
                if let vehicle = cachedVehicle(for: id) {
                    let distance = currentDistance > 0
                        ? min(currentDistance, MapConstants.vehicleCompactDistanceThreshold)
                        : MapConstants.vehicleCompactDistanceThreshold
                    animateCamera(
                        center: vehicle.coordinate,
                        distance: distance,
                        animation: .spring(response: 0.45, dampingFraction: 0.85)
                    )
                }
            case .stop, nil:
                isTrackingVehicle = false
            }
        }
    }

    var selectedStopID: String? {
        if case .stop(let id) = selection { return id }
        return nil
    }

    var selectedVehicleID: String? {
        if case .vehicle(let id) = selection { return id }
        return nil
    }

    var isPKPSelected: Bool {
        selectedCity.id == City.pkp.id
    }

    private(set) var isPitched3D: Bool = false
    private(set) var areStopsVisible: Bool = true
    private(set) var areStopTitlesVisible: Bool = false
    var currentHeading: Double = 0 {
        didSet {
            _cameraState.heading = currentHeading
        }
    }

    var currentPitch: Double {
        get { _cameraState.pitch }
        set {
            _cameraState.pitch = newValue
            applyPitchFlag(newValue)
        }
    }

    var currentDistance: Double {
        get { _cameraState.distance }
        set {
            _cameraState.distance = newValue
            applyDistanceDerivedFlags(newValue)
        }
    }

    var currentCenter: CLLocationCoordinate2D {
        get { _cameraState.center }
        set { _cameraState.center = newValue }
    }

    var visibleRegion: MKCoordinateRegion {
        get { _cameraState.region }
        set {
            _cameraState.region = newValue
            updateStops()
            updateRenderedVehicles()
        }
    }

    private static func computeVisibility(for distance: Double, isPKP: Bool) -> (
        stopsVisible: Bool,
        stopTitlesVisible: Bool,
        vehiclesVisible: Bool,
        vehicleCompact: Bool
    ) {
        let stopThreshold = isPKP ? MapConstants.pkpStopVisibilityDistanceThreshold : MapConstants.stopVisibilityDistanceThreshold
        return (
            stopsVisible: distance <= stopThreshold,
            stopTitlesVisible: distance <= MapConstants.stopTitleVisibilityDistanceThreshold,
            // When PKP is explicitly selected, vehicles remain visible at all zoom levels (thinned when dense).
            vehiclesVisible: isPKP || distance <= MapConstants.vehicleVisibilityDistanceThreshold,
            vehicleCompact: distance > MapConstants.vehicleCompactDistanceThreshold
        )
    }

    private func applyPitchFlag(_ pitch: Double) {
        let newPitched = pitch > 1.0
        if isPitched3D != newPitched {
            isPitched3D = newPitched
        }
    }

    private func applyDistanceDerivedFlags(_ distance: Double) {
        let visibility = Self.computeVisibility(for: distance, isPKP: isPKPSelected)
        if areStopsVisible != visibility.stopsVisible {
            areStopsVisible = visibility.stopsVisible
        }
        if areStopTitlesVisible != visibility.stopTitlesVisible {
            areStopTitlesVisible = visibility.stopTitlesVisible
        }
        if isVehiclesVisible != visibility.vehiclesVisible {
            isVehiclesVisible = visibility.vehiclesVisible
            if !visibility.vehiclesVisible {
                vehicles = []
                stopVehiclePolling()
            } else {
                startVehiclePolling()
            }
        }
        if isVehicleCompactDisplayMode != visibility.vehicleCompact {
            isVehicleCompactDisplayMode = visibility.vehicleCompact
        }
    }

    private func syncDerivedCameraProperties(from state: CameraState) {
        applyPitchFlag(state.pitch)
        applyDistanceDerivedFlags(state.distance)
        if abs(currentHeading - state.heading) >= 0.5 {
            currentHeading = state.heading
        }
    }

    private struct RequestKey: Equatable {
        let cityID: String
        let bbox: BoundingBox
    }

    @ObservationIgnored private var activeRequest: RequestKey?

    /// Whether the currently selected city's viewport has a request in flight.
    private(set) var isLoading: Bool = false

    /// The reason for the current load, or `nil` when nothing is in flight.
    private(set) var loadingPhase: StopLoadingPhase?

    /// Failure message for the currently selected city, if any. Errors are
    /// tracked per city so a failed fetch for city A never surfaces while
    /// viewing city B.
    private(set) var errorMessage: String?

    private func updateLoadingAndErrorStates() {
        let newLoading = activeRequest?.cityID == selectedCity.id
        if isLoading != newLoading { isLoading = newLoading }
        let newError = errorsByCity[selectedCity.id]
        if errorMessage != newError { errorMessage = newError }
    }

    /// The stop currently selected, looked up by `selectedStopID`. Derived —
    /// never set this; write to `selection` instead.
    var selectedStop: Stop? {
        selectedStopID.flatMap(cachedStop)
    }

    /// Looks up a stop in the session cache by its identifier.
    func cachedStop(for id: String) -> Stop? {
        cachedStopsByID[id]
    }

    private let apiClient: any TransitDataProviding
    private let persistence: any CameraPersistenceStore
    private let debounceDuration: Duration

    // `nonisolated(unsafe)`: only mutated from `@MainActor` methods, read from
    // `deinit` (nonisolated by definition). `Task` is `Sendable`, so cancelling
    // from any context is safe; the reference itself is never read concurrently.
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var debounceTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var vehiclePollingTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var vehicleThinningTask: Task<Void, Never>?
    @ObservationIgnored private var vehicleThinningGeneration = UUID()
    /// Region for which `stops` was last updated, expanded by `MapConstants.viewportBufferFactor`.
    @ObservationIgnored private var lastBufferedRegion: MKCoordinateRegion?
    /// Region for which `vehicles` was last thinned, expanded by `MapConstants.viewportBufferFactor`.
    @ObservationIgnored private var lastVehicleBufferedRegion: MKCoordinateRegion?
    @ObservationIgnored private var inFlightTiles: Set<MapTile> = []
    /// Session-only stop cache for the selected city.
    @ObservationIgnored private var cachedStopsByID: [String: Stop] = [:]
    /// Tiles whose bbox has been fetched successfully in this session.
    @ObservationIgnored private var fetchedTiles: Set<MapTile> = []

    /// Live vehicles cache for current session/city.
    @ObservationIgnored private var cachedVehicles: [VehiclePosition] = []

    @ObservationIgnored private var errorsByCity: [String: String] = [:]
    /// Generation token guarding against stale responses: each fetch gets a
    /// fresh token, and a response only applies if it still matches.
    @ObservationIgnored private var requestGeneration = UUID()
    /// City of the last request, even when no data has arrived yet. Lets the
    /// loading phase distinguish a switch from a cold start.
    @ObservationIgnored private var lastRequestedCityID: String?

    init(
        apiClient: any TransitDataProviding = ZbiorkomAPIClient.shared,
        initialCity: City? = nil,
        persistence: any CameraPersistenceStore = UserDefaultsCameraPersistenceStore(),
        debounceDuration: Duration = MapConstants.cameraFetchDebounce
    ) {
        self.apiClient = apiClient
        self.persistence = persistence
        self.debounceDuration = debounceDuration

        let chosenCity = initialCity
            ?? persistence.loadLastSelectedCityID().flatMap { id in City.allCities.first(where: { $0.id == id }) }
            ?? .warsaw
        self.selectedCity = chosenCity

        let initialCamera = Self.initialCamera(
            for: chosenCity,
            savedCamera: initialCity == nil ? persistence.loadSavedCamera() : nil
        )
        self._cameraState = initialCamera.state
        self._cameraPosition = initialCamera.position

        let visibility = Self.computeVisibility(
            for: initialCamera.state.distance,
            isPKP: chosenCity.id == City.pkp.id
        )
        self.areStopsVisible = visibility.stopsVisible
        self.areStopTitlesVisible = visibility.stopTitlesVisible
        self.isVehiclesVisible = visibility.vehiclesVisible
        self.isVehicleCompactDisplayMode = visibility.vehicleCompact
    }

    private static func initialCamera(
        for city: City,
        savedCamera: (latitude: Double, longitude: Double, distance: Double)?
    ) -> (state: CameraState, position: MapCameraPosition) {
        if let saved = savedCamera,
           saved.latitude.isFinite, saved.longitude.isFinite, saved.distance.isFinite, saved.distance > 0,
           (-90.0...90.0).contains(saved.latitude), (-180.0...180.0).contains(saved.longitude) {
            let savedCoord = CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude)
            let isWithinBounds = city.id == City.pkp.id
                || savedCoord.distance(to: city.coordinate) <= city.coverageRadiusMeters
            if isWithinBounds {
                let delta = max(0.001, min(180.0, saved.distance / MapConstants.metresPerDegreeLatitude))
                let region = MKCoordinateRegion(
                    center: savedCoord,
                    span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
                )
                let state = CameraState(region: region, distance: saved.distance, center: savedCoord)
                let position: MapCameraPosition = .camera(MapCamera(
                    centerCoordinate: savedCoord,
                    distance: saved.distance,
                    heading: 0,
                    pitch: 0
                ))
                return (state, position)
            }
        }

        let defaultRegion = MKCoordinateRegion(
            center: city.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: city.defaultLatitudeDelta,
                longitudeDelta: city.defaultLongitudeDelta
            )
        )
        let state = CameraState(
            region: defaultRegion,
            distance: approximateDistance(for: defaultRegion),
            center: city.coordinate
        )
        return (state, .region(defaultRegion))
    }

    /// Persists current camera center and zoom distance to non-volatile storage.
    func saveCameraPosition() {
        persistence.saveCamera(
            latitude: currentCenter.latitude,
            longitude: currentCenter.longitude,
            distance: currentDistance
        )
    }

    deinit {
        activeFetchTask?.cancel()
        debounceTask?.cancel()
        vehiclePollingTask?.cancel()
        vehicleThinningTask?.cancel()
    }

    func repositionCameraForCurrentCity() {
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
        cameraState = CameraState(
            region: newRegion,
            distance: Self.approximateDistance(for: newRegion),
            center: selectedCity.coordinate
        )
        isTrackingUser = false
    }

    /// MapKit does not expose a synchronous camera distance when only a region
    /// is known. The visible height in metres is a close enough proxy for the
    /// distance threshold: 0.08° ≈ 9 km for a city, 5° ≈ 555 km for PKP.
    static func approximateDistance(for region: MKCoordinateRegion) -> Double {
        region.span.latitudeDelta * MapConstants.metresPerDegreeLatitude
    }

    func handleCameraChange(to context: MapCameraUpdateContext) {
        let newState = CameraState(
            region: context.region,
            heading: context.camera.heading,
            pitch: context.camera.pitch,
            distance: context.camera.distance,
            center: context.camera.centerCoordinate
        )
        applyCameraState(newState)
    }

    func applyCameraState(_ newState: CameraState) {
        releaseTrackingIfRoaming(to: newState.center)
        guard newState != cameraState else { return }
        cameraState = newState
        updateStops()
        updateRenderedVehicles()
        scheduleViewportFetch()
        updateRegionSuggestion()
    }

    private func releaseTrackingIfRoaming(to center: CLLocationCoordinate2D) {
        if isTrackingUser, let userLocation = LocationManager.shared.userLocation,
           center.distance(to: userLocation.coordinate) > 150 {
            isTrackingUser = false
        }
        if isTrackingVehicle, let selectedID = selectedVehicleID, let vehicle = cachedVehicle(for: selectedID),
           center.distance(to: vehicle.coordinate) > 200 {
            isTrackingVehicle = false
        }
    }

    private func animateCamera(
        center: CLLocationCoordinate2D,
        distance: Double,
        pitch: Double? = nil,
        animation: Animation
    ) {
        let camera = MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: currentHeading,
            pitch: pitch ?? currentPitch
        )
        withAnimation(animation) {
            cameraPosition = .camera(camera)
        }
    }

    /// Centers the map camera on the user's coordinate with a smooth spring animation.
    func centerOnUserLocation(coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        isTrackingUser = true
        animateCamera(
            center: coordinate,
            distance: min(currentDistance, 4000),
            animation: .spring(response: 0.45, dampingFraction: 0.8)
        )
        currentCenter = coordinate
    }

    /// Flattens the map view to 2D (pitch = 0) while keeping current center, distance, and heading intact.
    func resetPitchTo2D() {
        animateCamera(
            center: currentCenter,
            distance: currentDistance,
            pitch: 0,
            animation: .spring(response: 0.4, dampingFraction: 0.85)
        )
        currentPitch = 0
    }

    /// Toggles between explore (normal) and satellite map rendering modes.
    func toggleMapMode() {
        selectedMapMode = (selectedMapMode == .satellite) ? .explore : .satellite
    }

    // MARK: - Region Suggestion

    /// Evaluates whether the current camera viewport belongs to a different transit network,
    /// updating `suggestedCity`.
    func updateRegionSuggestion() {
        let center = cameraState.center
        let span = cameraState.region.span

        // Clear dismissed city memory if the user has panned far away from it (> 1.5x its radius)
        if let dismissed = dismissedCityID,
           let city = City.city(id: dismissed),
           center.distance(to: city.coordinate) > city.coverageRadiusMeters * 1.5 {
            dismissedCityID = nil
        }

        let newSuggestion = Self.detectSuggestedCity(
            center: center,
            regionSpan: span,
            currentCity: selectedCity,
            allCities: City.allCities,
            dismissedCityID: dismissedCityID
        )

        if suggestedCity != newSuggestion {
            suggestedCity = newSuggestion
        }
    }

    /// Determines whether the viewport is focused on a different transit network.
    static func detectSuggestedCity(
        center: CLLocationCoordinate2D,
        regionSpan: MKCoordinateSpan,
        currentCity: City,
        allCities: [City] = City.allCities,
        dismissedCityID: String? = nil
    ) -> City? {
        // Only evaluate when zoomed into city or regional scale (span ≤ 0.6° ≈ 65 km).
        // Macro / nationwide zooms shouldn't trigger local city switch suggestions.
        guard regionSpan.latitudeDelta <= 0.6 else { return nil }

        var closestMatch: (city: City, distance: CLLocationDistance)?
        for city in allCities {
            guard city.id != City.pkp.id, city.id != currentCity.id else { continue }
            let radius = city.coverageRadiusMeters
            guard radius > 0 else { continue }

            // Fast bounding-box prefilter before great-circle distance.
            let maxDeltaLat = (radius / MapConstants.metresPerDegreeLatitude) * 1.05
            guard abs(center.latitude - city.coordinate.latitude) <= maxDeltaLat else { continue }

            let distance = center.distance(to: city.coordinate)
            guard distance <= radius else { continue }
            if distance < (closestMatch?.distance ?? .infinity) {
                closestMatch = (city, distance)
            }
        }

        guard let best = closestMatch else { return nil }

        // If the user dismissed this specific city, don't nag them while they stay in it
        if best.city.id == dismissedCityID {
            return nil
        }

        // If current city is not PKP, verify the viewport is not still in the current city's territory.
        // Hysteresis: best candidate must be closer than current city by at least 3 km.
        if currentCity.id != City.pkp.id {
            let currentDistance = center.distance(to: currentCity.coordinate)
            if best.distance >= currentDistance - 3_000 {
                return nil
            }
        }

        return best.city
    }

    /// Selects a new city, optionally repositioning the camera to the city's center.
    func selectCity(_ city: City, repositionCamera: Bool = true) {
        guard city != selectedCity else { return }
        selectedCity = city
        persistence.saveLastSelectedCityID(city.id)
        selection = nil
        isRetryableError = true
        clearStopCache()
        clearVehicleCache()
        stopVehiclePolling()
        if repositionCamera {
            repositionCameraForCurrentCity()
        } else {
            syncDerivedCameraProperties(from: cameraState)
        }
        suggestedCity = nil
        loadStopsForSelectedCity()
        startVehiclePolling()
    }

    /// Switches the active city to the currently suggested city without moving the camera,
    /// so the user retains their exact viewing position.
    func switchToSuggestedCity() {
        guard let city = suggestedCity else { return }
        selectCity(city, repositionCamera: false)
    }

    /// Dismisses the current region switch suggestion.
    func dismissSuggestedCity() {
        if let currentSuggestion = suggestedCity {
            dismissedCityID = currentSuggestion.id
            suggestedCity = nil
        }
    }

    // MARK: - Stop fetching (tiled viewport coverage)

    /// Why the current viewport does or does not need a request.
    private enum ViewportLoad {
        case cached
        case fetch(bbox: BoundingBox, tiles: Set<MapTile>)
        case invalid
    }

    /// Loads stops for the selected city's current viewport. Idempotent while
    /// a request for the same area is in flight or every required tile is
    /// already cached.
    func loadStopsForSelectedCity() {
        debounceTask?.cancel()
        debounceTask = nil
        fetchCurrentViewport()
    }

    // MARK: - Scene phase

    /// Cancels in-flight network work when the scene backgrounds. The session
    /// cache is kept in memory so returning to the foreground stays instant.
    func pauseForBackground() {
        #if DEBUG
        Logger.mapCache.debug("Pausing for background: cancelling active fetch and debounced tasks for city \(self.selectedCity.id, privacy: .public)")
        #endif
        debounceTask?.cancel()
        debounceTask = nil
        stopVehiclePolling()
        vehicleThinningTask?.cancel()
        vehicleThinningTask = nil
        cancelActiveFetch()
    }

    /// Maps an error to a short, localized message. Non-`LocalizedError`
    /// failures (including generic test doubles) get a stable app-owned string
    /// instead of Foundation's often-English `localizedDescription`.
    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(localized: "error.generic")
    }

    private func fetchCurrentViewport() {
        guard areStopsVisible else {
            cancelActiveFetch()
            updateStops()
            return
        }
        let city = selectedCity
        switch loadDecision(for: cameraState.region) {
        case .cached:
            cancelActiveFetch()
            errorsByCity[city.id] = nil
            updateLoadingAndErrorStates()
            updateStops(force: true)
        case .fetch(let bbox, let tiles):
            startFetch(city: city, bbox: bbox, tiles: tiles)
        case .invalid:
            cancelActiveFetch()
        }
    }

    /// Debounces fetches triggered by `.onEnd` camera changes.
    /// Skips debounce and fetch entirely if all visible tiles are covered or already in flight (2P1-6).
    private func scheduleViewportFetch() {
        guard areStopsVisible else {
            cancelActiveFetch()
            updateStops()
            return
        }
        let visibleTiles = MapTileGrid.visibleTiles(in: cameraState.region)
        let missingTiles = visibleTiles.filter { !fetchedTiles.contains($0) }
        if missingTiles.isEmpty || missingTiles == inFlightTiles {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            self.debounceTask = nil
            self.fetchCurrentViewport()
        }
    }

    /// Decides whether the visible tiles are already covered by the session
    /// cache, and if not, which missing tiles to request in one bbox.
    private func loadDecision(for region: MKCoordinateRegion) -> ViewportLoad {
        let visibleTiles = MapTileGrid.visibleTiles(in: region)
        guard !visibleTiles.isEmpty else {
            Logger.mapCache.debug("Load decision: invalid region (visible tiles is empty)")
            return .invalid
        }
        let missingTiles = visibleTiles.filter { !fetchedTiles.contains($0) }
        guard !missingTiles.isEmpty else {
            Logger.mapCache.debug("Cache HIT: all \(visibleTiles.count, privacy: .public) visible tiles at zoom \(MapTileGrid.zoom, privacy: .public) covered. Cached stops: \(self.cachedStopsByID.count, privacy: .public)")
            return .cached
        }
        guard let bbox = MapTileGrid.boundingBox(covering: missingTiles) else {
            Logger.mapCache.debug("Load decision: failed to create bounding box for \(missingTiles.count, privacy: .public) missing tiles")
            return .invalid
        }
        Logger.mapCache.debug("Cache MISS: \(missingTiles.count, privacy: .public) of \(visibleTiles.count, privacy: .public) visible tiles missing at zoom \(MapTileGrid.zoom, privacy: .public). Querying bbox: \(bbox.queryValue, privacy: .public)")
        return .fetch(bbox: bbox, tiles: missingTiles)
    }

    private func startFetch(city: City, bbox: BoundingBox, tiles: Set<MapTile>) {
        let requestKey = RequestKey(cityID: city.id, bbox: bbox)
        guard activeRequest != requestKey else {
            #if DEBUG
            Logger.mapCache.debug("Start fetch skipped: already in flight for \(city.id, privacy: .public):\(bbox.queryValue, privacy: .public)")
            #endif
            return
        }

        #if DEBUG
        Logger.mapCache.debug("Starting fetch for city \(city.id, privacy: .public), bbox: \(bbox.queryValue, privacy: .public), missing tiles: \(tiles.count, privacy: .public)")
        #endif

        activeFetchTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        inFlightTiles = tiles
        requestGeneration = UUID()
        let generation = requestGeneration
        errorsByCity[city.id] = nil
        activeRequest = requestKey
        updateLoadingAndErrorStates()

        loadingPhase = (lastRequestedCityID == nil) ? .initial : ((lastRequestedCityID == city.id) ? .refresh : .citySwitch)
        lastRequestedCityID = city.id

        // Existing cached stops stay on screen while the new tiles load.
        updateStops()

        activeFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetchedStops = try await self.apiClient.fetchStops(city: city.id, bbox: bbox)
                guard !Task.isCancelled, generation == self.requestGeneration else {
                    #if DEBUG
                    Logger.mapCache.debug("Fetch result discarded for \(city.id, privacy: .public): cancelled or generation mismatch")
                    #endif
                    return
                }
                guard self.selectedCity.id == city.id else {
                    #if DEBUG
                    Logger.mapCache.debug("Fetch result discarded: selected city changed to \(self.selectedCity.id, privacy: .public)")
                    #endif
                    return
                }
                for stop in fetchedStops {
                    self.cachedStopsByID[stop.id] = stop
                }
                // Empty results still mark the tiles as fetched: an empty
                // viewport is authoritative for this session and must not
                // trigger a request on every settle.
                self.fetchedTiles.formUnion(tiles)
                self.inFlightTiles.removeAll()
                self.errorsByCity.removeValue(forKey: city.id)
                self.updateStops(force: true)
                self.activeRequest = nil
                self.loadingPhase = nil
                self.updateLoadingAndErrorStates()
                Logger.mapCache.debug("Fetch completed for \(city.id, privacy: .public): +\(fetchedStops.count, privacy: .public) stops (total cached: \(self.cachedStopsByID.count, privacy: .public)), +\(tiles.count, privacy: .public) tiles (total tiles: \(self.fetchedTiles.count, privacy: .public))")
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), generation == self.requestGeneration else {
                    Logger.mapCache.debug("Fetch error discarded for \(city.id, privacy: .public): cancelled or generation mismatch")
                    return
                }
                if self.selectedCity.id == city.id {
                    Logger.mapCache.error("Fetch failed for \(city.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.inFlightTiles.removeAll()
                    self.errorsByCity[city.id] = Self.userFacingMessage(for: error)
                    self.activeRequest = nil
                    self.loadingPhase = nil
                    self.updateLoadingAndErrorStates()
                }
            }
        }
    }

    private func cancelActiveFetch() {
        if activeFetchTask != nil {
            Logger.mapCache.debug("Cancelling active fetch for city \(self.selectedCity.id, privacy: .public)")
        }
        activeFetchTask?.cancel()
        activeFetchTask = nil
        inFlightTiles.removeAll()
        // Invalidate the generation so a task already past its guard writes
        // nothing after cancellation.
        requestGeneration = UUID()
        loadingPhase = nil
        if activeRequest != nil {
            activeRequest = nil
            updateLoadingAndErrorStates()
        }
    }

    /// Drops every cached stop and tile for the previous city. The cache is
    /// session-only and never written to UserDefaults or disk.
    private func clearStopCache() {
        #if DEBUG
        Logger.mapCache.debug("Clearing stop cache: purging \(self.cachedStopsByID.count, privacy: .public) cached stops and \(self.fetchedTiles.count, privacy: .public) fetched tiles for city \(self.selectedCity.id, privacy: .public)")
        #endif
        debounceTask?.cancel()
        debounceTask = nil
        lastBufferedRegion = nil
        cancelActiveFetch()
        cachedStopsByID.removeAll()
        fetchedTiles.removeAll()
        errorsByCity.removeAll()
        updateLoadingAndErrorStates()
        updateStops(force: true)
    }

    // MARK: - Marker rendering

    /// Evaluates whether the current visible region is sufficiently covered by the buffered region
    /// so that re-thinning can be safely skipped.
    static func isRegion(_ inner: MKCoordinateRegion, safelyContainedIn outer: MKCoordinateRegion) -> Bool {
        guard let innerBounds = BoundingBox(inner),
              let outerBounds = BoundingBox(outer),
              outerBounds.contains(innerBounds) else {
            return false
        }

        // Check if zoom scale hasn't shifted significantly
        let nominalOuterLatSpan = outer.span.latitudeDelta / MapConstants.viewportBufferFactor
        let latRatio = inner.span.latitudeDelta / max(nominalOuterLatSpan, 1e-6)
        return abs(latRatio - 1.0) <= MapConstants.zoomChangeRatioThreshold
    }

    /// Computes an expanded buffered region for a given viewport region.
    static func bufferedRegion(for region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta * MapConstants.viewportBufferFactor,
                longitudeDelta: region.span.longitudeDelta * MapConstants.viewportBufferFactor
            )
        )
    }

    /// Pure, thread-safe computation of visible stops for a region (no thinning needed below 3,000 m).
    nonisolated static func computeRenderedStops(
        from cachedStops: some Sequence<Stop>,
        in region: MKCoordinateRegion
    ) -> [Stop] {
        guard let bounds = BoundingBox(region) else { return [] }
        return cachedStops
            .filter { bounds.contains(latitude: $0.latitude, longitude: $0.longitude) }
            .sorted { $0.id < $1.id }
    }

    /// Fast synchronous update of visible stops for the current viewport.
    func updateStops(force: Bool = false) {
        guard areStopsVisible, !cachedStopsByID.isEmpty else {
            lastBufferedRegion = nil
            if !stops.isEmpty {
                stops = []
            }
            return
        }

        let currentRegion = cameraState.region
        guard BoundingBox(currentRegion) != nil else { return }

        if !force, let lastBuffered = lastBufferedRegion,
           Self.isRegion(currentRegion, safelyContainedIn: lastBuffered) {
            return
        }

        let targetBuffer = Self.bufferedRegion(for: currentRegion)
        lastBufferedRegion = targetBuffer
        let rendered = Self.computeRenderedStops(from: cachedStopsByID.values, in: targetBuffer)
        if rendered != stops {
            stops = rendered
        }
    }

    // MARK: - Live Vehicles

    func startVehiclePolling() {
        guard isVehiclesVisible, vehiclePollingTask == nil else { return }
        vehiclePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchVehiclesForCurrentViewport()
                do {
                    try await Task.sleep(for: .seconds(MapConstants.vehicleTTL))
                } catch {
                    break
                }
            }
        }
    }

    func stopVehiclePolling() {
        vehiclePollingTask?.cancel()
        vehiclePollingTask = nil
    }

    func fetchVehiclesForCurrentViewport() async {
        guard isVehiclesVisible else { return }
        let city = selectedCity
        let region = cameraState.region
        guard BoundingBox(region) != nil else { return }

        let buffer = Self.bufferedRegion(for: region)
        guard let bbox = BoundingBox(buffer)?.clamped else { return }

        do {
            let fetched = try await apiClient.fetchVehicles(city: city.id, bbox: bbox)
            guard !Task.isCancelled, selectedCity.id == city.id else { return }

            if !isRetryableError {
                errorMessage = nil
                isRetryableError = true
            }

            await updateCachedVehiclesAsync(fetched, for: buffer)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, selectedCity.id == city.id else { return }
            Logger.api.error("Failed to fetch vehicles for \(city.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Instruction: don't include retry action for vehicle network failures
            isRetryableError = false
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func updateCachedVehiclesAsync(_ newVehicles: [VehiclePosition], for buffer: MKCoordinateRegion) async {
        cachedVehicles = newVehicles

        // If tracked vehicle moved, smoothly update camera
        if isTrackingVehicle, let selectedID = selectedVehicleID, let tracked = cachedVehicle(for: selectedID) {
            let targetDistance = currentDistance > 0 ? currentDistance : MapConstants.vehicleCompactDistanceThreshold
            animateCamera(
                center: tracked.coordinate,
                distance: targetDistance,
                animation: .easeInOut(duration: 1.0)
            )
        }

        await updateRenderedVehiclesAsync(for: buffer, force: true)
    }

    private func clearVehicleCache() {
        vehicleThinningTask?.cancel()
        vehicleThinningTask = nil
        cachedVehicles.removeAll()
        vehicles.removeAll()
        lastVehicleBufferedRegion = nil
    }

    func cachedVehicle(for id: String) -> VehiclePosition? {
        cachedVehicles.first(where: { $0.id == id })
    }

    nonisolated private struct VehicleThinningPlan: Sendable {
        let vehicles: [VehiclePosition]
        let region: MKCoordinateRegion
        let selectedVehicleID: String?
        let generation: UUID
    }

    private func prepareVehicleThinning(for buffer: MKCoordinateRegion?, force: Bool) -> VehicleThinningPlan? {
        guard isVehiclesVisible, !cachedVehicles.isEmpty else {
            vehicleThinningTask?.cancel()
            vehicleThinningTask = nil
            lastVehicleBufferedRegion = nil
            if !vehicles.isEmpty {
                vehicles = []
            }
            return nil
        }

        let currentRegion = cameraState.region
        guard BoundingBox(currentRegion) != nil else { return nil }

        let targetBuffer = buffer ?? Self.bufferedRegion(for: currentRegion)

        if !force, buffer == nil, let last = lastVehicleBufferedRegion,
           Self.isRegion(currentRegion, safelyContainedIn: last) {
            return nil
        }

        let maxCount = MapConstants.maxRenderedVehicles
        let generation = UUID()
        vehicleThinningGeneration = generation

        if cachedVehicles.count <= maxCount {
            vehicleThinningTask?.cancel()
            vehicleThinningTask = nil
            let rendered = Self.computeRenderedVehicles(
                from: cachedVehicles,
                in: targetBuffer,
                selectedVehicleID: selectedVehicleID,
                maxRenderedVehicles: maxCount
            )
            applyRenderedVehicles(rendered, for: targetBuffer, generation: generation)
            return nil
        }

        return VehicleThinningPlan(
            vehicles: cachedVehicles,
            region: targetBuffer,
            selectedVehicleID: selectedVehicleID,
            generation: generation
        )
    }

    func updateRenderedVehiclesAsync(for buffer: MKCoordinateRegion? = nil, force: Bool = false) async {
        guard let plan = prepareVehicleThinning(for: buffer, force: force) else { return }

        vehicleThinningTask?.cancel()
        let rendered = await Task.detached(priority: .userInitiated) {
            Self.computeRenderedVehicles(
                from: plan.vehicles,
                in: plan.region,
                selectedVehicleID: plan.selectedVehicleID,
                maxRenderedVehicles: MapConstants.maxRenderedVehicles
            )
        }.value

        guard !Task.isCancelled, plan.generation == vehicleThinningGeneration else { return }
        vehicleThinningTask = nil
        applyRenderedVehicles(rendered, for: plan.region, generation: plan.generation)
    }

    func updateRenderedVehicles(for buffer: MKCoordinateRegion? = nil, force: Bool = false) {
        vehicleThinningTask?.cancel()
        vehicleThinningTask = Task {
            await updateRenderedVehiclesAsync(for: buffer, force: force)
        }
    }

    private func applyRenderedVehicles(_ rendered: [VehiclePosition], for bufferedRegion: MKCoordinateRegion, generation: UUID) {
        guard generation == vehicleThinningGeneration else { return }
        lastVehicleBufferedRegion = bufferedRegion
        if rendered != vehicles {
            withAnimation(.easeInOut(duration: 1.0)) {
                vehicles = rendered
            }
        }
    }

    nonisolated static func computeRenderedVehicles(
        from cachedVehicles: [VehiclePosition],
        in region: MKCoordinateRegion,
        selectedVehicleID: String?,
        maxRenderedVehicles: Int
    ) -> [VehiclePosition] {
        guard let bounds = BoundingBox(region) else { return [] }

        let visibleVehicles = cachedVehicles.filter {
            bounds.contains(latitude: $0.latitude, longitude: $0.longitude)
        }

        var rendered: [VehiclePosition]
        if visibleVehicles.count > maxRenderedVehicles {
            rendered = thinnedVehicles(visibleVehicles, region: region, selectedVehicleID: selectedVehicleID, maxRenderedVehicles: maxRenderedVehicles)
        } else {
            rendered = visibleVehicles.sorted { $0.id < $1.id }
        }

        if let selectedVehicleID,
           let selected = cachedVehicles.first(where: { $0.id == selectedVehicleID }),
           bounds.contains(latitude: selected.latitude, longitude: selected.longitude),
           !rendered.contains(where: { $0.id == selectedVehicleID }) {
            rendered.append(selected)
            rendered.sort { $0.id < $1.id }
        }

        return rendered
    }

    /// World-aligned spatial grid steps derived from the region span.
    nonisolated private static func thinningSteps(for region: MKCoordinateRegion) -> (latStep: Double, lonStep: Double) {
        let latSpan = max(region.span.latitudeDelta, 1e-6)
        let lonSpan = max(region.span.longitudeDelta, 1e-6)
        // With at most 12 cells per axis, a viewport can intersect at most 13x13 = 169 cells <= maxRenderedVehicles.
        let targetLatStep = latSpan / 12.0
        let targetLonStep = lonSpan / 12.0
        let latStep = pow(2.0, ceil(log2(targetLatStep)))
        let lonStep = pow(2.0, ceil(log2(targetLonStep)))
        return (max(latStep, 1e-6), max(lonStep, 1e-6))
    }

    /// Grid-based thinning: keep one deterministic representative per cell of
    /// a world-aligned spatial grid laid over the visible region.
    nonisolated static func thinnedVehicles(
        _ rawVehicles: [VehiclePosition],
        region: MKCoordinateRegion?,
        selectedVehicleID: String?,
        maxRenderedVehicles: Int
    ) -> [VehiclePosition] {
        guard let region = region, let bounds = BoundingBox(region) else { return [] }
        let (latStep, lonStep) = thinningSteps(for: region)
        var buckets: [Int: VehiclePosition] = [:]
        for vehicle in rawVehicles {
            guard bounds.contains(latitude: vehicle.latitude, longitude: vehicle.longitude) else { continue }
            let col = Int(floor(vehicle.longitude / lonStep))
            let row = Int(floor(vehicle.latitude / latStep))
            let cell = (row &* 73856093) ^ (col &* 19349663)

            if let current = buckets[cell] {
                if vehicle.id == selectedVehicleID || (current.id != selectedVehicleID && vehicle.id < current.id) {
                    buckets[cell] = vehicle
                }
            } else {
                buckets[cell] = vehicle
            }
        }
        let sorted = buckets.values.sorted { $0.id < $1.id }
        return sorted.count > maxRenderedVehicles ? Array(sorted.prefix(maxRenderedVehicles)) : sorted
    }
}

