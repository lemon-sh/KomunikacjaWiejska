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
            var reg = region
            if let center = center {
                reg.center = center
            }
            self.region = reg
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
    }

    var cameraState: CameraState {
        get { _cameraState }
        set {
            _cameraState = newValue
            syncDerivedCameraProperties(from: newValue)
        }
    }

    /// Markers currently rendered on the map. This is the visible, thinned
    /// view of the session stop cache.
    private(set) var stops: [Stop] = []
    /// Marker selection source of truth: the map writes the tagged stop ID,
    /// the detail sheet is derived from it.
    var selectedStopID: String?
    var isShowingCityPicker: Bool = false
    var selectedMapMode: MapMode = .explore
    var isShowingMapModes: Bool = false
    var isTrackingUser: Bool = false

    private(set) var isCompactDisplayMode: Bool = true
    private(set) var isPitched3D: Bool = false
    private(set) var areStopsVisible: Bool = true
    var currentHeading: Double = 0 {
        didSet {
            _cameraState.heading = currentHeading
        }
    }

    var currentPitch: Double {
        get { _cameraState.pitch }
        set {
            _cameraState.pitch = newValue
            let newPitched = newValue > 1.0
            if isPitched3D != newPitched {
                isPitched3D = newPitched
            }
        }
    }

    var currentDistance: Double {
        get { _cameraState.distance }
        set {
            _cameraState.distance = newValue
            let newCompact = newValue > compactDisplayDistanceThreshold
            if isCompactDisplayMode != newCompact {
                isCompactDisplayMode = newCompact
            }
            let newVisible = newValue <= stopVisibilityDistanceThreshold
            if areStopsVisible != newVisible {
                areStopsVisible = newVisible
            }
        }
    }

    var currentCenter: CLLocationCoordinate2D {
        get { _cameraState.center }
        set { _cameraState.center = newValue }
    }

    var visibleRegion: MKCoordinateRegion? {
        get { _cameraState.region }
        set {
            if let region = newValue {
                _cameraState.region = region
                updateStops()
            }
        }
    }

    private func syncDerivedCameraProperties(from state: CameraState) {
        let newCompact = state.distance > compactDisplayDistanceThreshold
        if isCompactDisplayMode != newCompact {
            isCompactDisplayMode = newCompact
        }
        let newPitched = state.pitch > 1.0
        if isPitched3D != newPitched {
            isPitched3D = newPitched
        }
        let newVisible = state.distance <= stopVisibilityDistanceThreshold
        if areStopsVisible != newVisible {
            areStopsVisible = newVisible
        }
        if abs(currentHeading - state.heading) >= 0.5 {
            currentHeading = state.heading
        }
    }

    struct RequestKey: Hashable, Sendable {
        let cityID: String
        let bbox: BoundingBox

        init(cityID: String, bbox: BoundingBox) {
            self.cityID = cityID
            self.bbox = bbox
        }
    }

    private enum FetchState: Equatable {
        case idle
        case loading(RequestKey)
        case loaded(RequestKey)
        case failed(RequestKey)
    }

    @ObservationIgnored private var fetchState: FetchState = .idle

    /// Whether the currently selected city's viewport has a request in flight.
    private(set) var isLoading: Bool = false

    /// The reason for the current load, or `nil` when nothing is in flight.
    private(set) var loadingPhase: StopLoadingPhase?

    /// Failure message for the currently selected city, if any. Errors are
    /// tracked per city so a failed fetch for city A never surfaces while
    /// viewing city B.
    private(set) var errorMessage: String?

    private func updateLoadingAndErrorStates() {
        let newLoading: Bool
        if case .loading(let key) = fetchState {
            newLoading = key.cityID == selectedCity.id
        } else {
            newLoading = false
        }
        if isLoading != newLoading {
            isLoading = newLoading
        }

        let newError = errorsByCity[selectedCity.id]
        if errorMessage != newError {
            errorMessage = newError
        }
    }

    /// The stop currently selected, looked up by `selectedStopID`. Derived —
    /// never set this; write to `selectedStopID` instead.
    var selectedStop: Stop? {
        guard let selectedStopID = selectedStopID else { return nil }
        return cachedStopsByID[selectedStopID]
    }

    /// Looks up a stop in the session cache by its identifier.
    func cachedStop(for id: String) -> Stop? {
        cachedStopsByID[id]
    }

    /// Camera distance (in metres) above which stops are displayed as smaller
    /// compact points.
    let compactDisplayDistanceThreshold: Double = 6_000

    /// Camera distance (in metres) above which stops are no longer displayed at all.
    let stopVisibilityDistanceThreshold: Double = 12_000

    /// Keys for camera persistence in non-volatile storage.

    /// Hard ceiling on markers rendered at once; extra stops are thinned to
    /// one representative per grid cell (see `thinnedStops`).
    static let maxRenderedStops = 250

    private let apiClient: any StopsProviding
    private let persistence: any CameraPersistenceStore

    // `nonisolated(unsafe)`: only mutated from `@MainActor` methods, read from
    // `deinit` (nonisolated by definition). `Task` is `Sendable`, so cancelling
    // from any context is safe; the reference itself is never read concurrently.
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var inFlightTiles: Set<MapTile> = []
    /// Session-only stop cache for the selected city. Never persisted, and
    /// cleared on every city switch. Stop data is treated as stable for the
    /// lifetime of the app process, so entries never expire.
    @ObservationIgnored private var cachedStopsByID: [String: Stop] = [:]
    /// Tiles whose bbox has been fetched successfully in this session.
    @ObservationIgnored private var fetchedTiles: Set<MapTile> = []
    @ObservationIgnored private var errorsByCity: [String: String] = [:]
    /// Generation token guarding against stale responses: each fetch gets a
    /// fresh token, and a response only applies if it still matches.
    @ObservationIgnored private var requestGeneration = UUID()
    /// City of the last request, even when no data has arrived yet. Lets the
    /// loading phase distinguish a switch from a cold start.
    @ObservationIgnored private var lastRequestedCityID: String?

    init(
        apiClient: any StopsProviding = ZbiorkomAPIClient.shared,
        initialCity: City? = nil,
        persistence: any CameraPersistenceStore = UserDefaultsCameraPersistenceStore()
    ) {
        self.apiClient = apiClient
        self.persistence = persistence

        let chosenCity: City
        if let initialCity = initialCity {
            chosenCity = initialCity
        } else if let savedId = persistence.loadLastSelectedCityID(),
                  let found = City.allCities.first(where: { $0.id == savedId }) {
            chosenCity = found
        } else {
            chosenCity = .warsaw
        }

        self.selectedCity = chosenCity

        var restoredCamera: (center: CLLocationCoordinate2D, distance: Double)?
        if initialCity == nil,
           let saved = persistence.loadSavedCamera(),
           saved.latitude.isFinite, saved.longitude.isFinite, saved.distance.isFinite, saved.distance > 0,
           (-90.0...90.0).contains(saved.latitude), (-180.0...180.0).contains(saved.longitude) {
            let savedCoord = CLLocationCoordinate2D(latitude: saved.latitude, longitude: saved.longitude)
            let isWithinCityBounds: Bool
            if chosenCity.id == City.pkp.id {
                isWithinCityBounds = true
            } else {
                let cityLocation = CLLocation(latitude: chosenCity.coordinate.latitude, longitude: chosenCity.coordinate.longitude)
                let savedLocation = CLLocation(latitude: savedCoord.latitude, longitude: savedCoord.longitude)
                isWithinCityBounds = savedLocation.distance(from: cityLocation) <= chosenCity.coverageRadiusMeters
            }
            if isWithinCityBounds {
                restoredCamera = (center: savedCoord, distance: saved.distance)
            }
        }

        if let restored = restoredCamera {
            let delta = max(0.001, min(180.0, restored.distance / MapConstants.metresPerDegreeLatitude))
            let region = MKCoordinateRegion(
                center: restored.center,
                span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
            )
            self._cameraState = CameraState(
                region: region,
                distance: restored.distance,
                center: restored.center
            )
            self._cameraPosition = .camera(MapCamera(
                centerCoordinate: restored.center,
                distance: restored.distance,
                heading: 0,
                pitch: 0
            ))
            self.isCompactDisplayMode = restored.distance > compactDisplayDistanceThreshold
            self.areStopsVisible = restored.distance <= stopVisibilityDistanceThreshold
        } else {
            let initialRegion = MKCoordinateRegion(
                center: chosenCity.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: chosenCity.defaultLatitudeDelta,
                    longitudeDelta: chosenCity.defaultLongitudeDelta
                )
            )
            let initialDistance = Self.approximateDistance(for: initialRegion)
            self._cameraState = CameraState(
                region: initialRegion,
                distance: initialDistance,
                center: chosenCity.coordinate
            )
            self._cameraPosition = .region(initialRegion)
            self.isCompactDisplayMode = initialDistance > compactDisplayDistanceThreshold
            self.areStopsVisible = initialDistance <= stopVisibilityDistanceThreshold
        }
        self.isPitched3D = false
        self.currentHeading = 0
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
    /// compact-mode threshold: 0.08° ≈ 9 km for a city, 5° ≈ 555 km for PKP.
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
        guard newState != cameraState else {
            // Still evaluate tracking release; nothing to observe otherwise.
            releaseTrackingIfRoaming(to: newState.center)
            return
        }
        cameraState = newState
        updateStops()
        releaseTrackingIfRoaming(to: newState.center)
        scheduleViewportFetch()
        updateRegionSuggestion()
    }

    private func releaseTrackingIfRoaming(to center: CLLocationCoordinate2D) {
        guard isTrackingUser, let userLocation = LocationManager.shared.userLocation else { return }
        let cameraLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if cameraLoc.distance(from: userLocation) > 150 {
            isTrackingUser = false
        }
    }

    /// Centers the map camera on the user's coordinate with a smooth spring animation.
    func centerOnUserLocation(coordinate: CLLocationCoordinate2D?) {
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
            cameraState.center = coordinate
        }
    }

    /// Flattens the map view to 2D (pitch = 0) while keeping current center, distance, and heading intact.
    func resetPitchTo2D() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            let camera = MapCamera(
                centerCoordinate: currentCenter,
                distance: currentDistance,
                heading: currentHeading,
                pitch: 0
            )
            cameraPosition = .camera(camera)
            cameraState.pitch = 0
        }
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
        if let dismissed = dismissedCityID, let city = City.allCities.first(where: { $0.id == dismissed }) {
            let viewportLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let dismissedLoc = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
            if viewportLoc.distance(from: dismissedLoc) > city.coverageRadiusMeters * 1.5 {
                dismissedCityID = nil
            }
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

        let viewportLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)

        struct Candidate {
            let city: City
            let distance: CLLocationDistance
        }

        var candidates: [Candidate] = []
        for city in allCities {
            guard city.id != "pkp", city.id != currentCity.id else { continue }
            let radius = city.coverageRadiusMeters
            guard radius > 0 else { continue }

            // Fast bounding-box prefilter: 1 degree latitude is ~111 km everywhere.
            let maxDeltaLat = (radius / 111_000.0) * 1.05
            guard abs(center.latitude - city.coordinate.latitude) <= maxDeltaLat else { continue }

            let cityLocation = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
            let distance = viewportLocation.distance(from: cityLocation)
            if distance <= radius {
                candidates.append(Candidate(city: city, distance: distance))
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Pick the closest candidate city to viewport center
        candidates.sort { $0.distance < $1.distance }
        guard let best = candidates.first else { return nil }

        // If the user dismissed this specific city, don't nag them while they stay in it
        if best.city.id == dismissedCityID {
            return nil
        }

        // If current city is not PKP, verify the viewport is not still in the current city's territory.
        // Hysteresis: best candidate must be closer than current city by at least 3 km.
        if currentCity.id != City.pkp.id {
            let currentCityLocation = CLLocation(
                latitude: currentCity.coordinate.latitude,
                longitude: currentCity.coordinate.longitude
            )
            let currentDistance = viewportLocation.distance(from: currentCityLocation)
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
        selectedStopID = nil
        errorsByCity.removeAll()
        clearStopCache()
        if repositionCamera {
            repositionCameraForCurrentCity()
        }
        suggestedCity = nil
        loadStopsForSelectedCity()
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
            fetchState = .idle
            errorsByCity[city.id] = nil
            loadingPhase = nil
            updateLoadingAndErrorStates()
            updateStops()
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
        let missingTiles = visibleTiles.filter { !isTileCovered($0) }
        if missingTiles.isEmpty || missingTiles == inFlightTiles {
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: MapConstants.cameraFetchDebounce)
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
        let missingTiles = visibleTiles.filter { !isTileCovered($0) }
        guard !missingTiles.isEmpty else {
            let zoom = visibleTiles.first?.zoom ?? MapTile.zoom
            Logger.mapCache.debug("Cache HIT: all \(visibleTiles.count, privacy: .public) visible tiles at zoom \(zoom, privacy: .public) covered. Cached stops: \(self.cachedStopsByID.count, privacy: .public)")
            return .cached
        }
        guard let bbox = MapTileGrid.boundingBox(covering: missingTiles) else {
            Logger.mapCache.debug("Load decision: failed to create bounding box for \(missingTiles.count, privacy: .public) missing tiles")
            return .invalid
        }
        let zoom = visibleTiles.first?.zoom ?? MapTile.zoom
        Logger.mapCache.debug("Cache MISS: \(missingTiles.count, privacy: .public) of \(visibleTiles.count, privacy: .public) visible tiles missing at zoom \(zoom, privacy: .public). Querying bbox: \(bbox.queryValue, privacy: .public)")
        return .fetch(bbox: bbox, tiles: missingTiles)
    }

    /// A tile is covered if it has been fetched successfully in this session.
    /// With fixed-size Zoom 12 tiles, there is no ancestor hierarchy.
    private func isTileCovered(_ tile: MapTile) -> Bool {
        fetchedTiles.contains(tile)
    }

    private func startFetch(city: City, bbox: BoundingBox, tiles: Set<MapTile>) {
        let requestKey = RequestKey(cityID: city.id, bbox: bbox)
        guard fetchState != .loading(requestKey) else {
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
        fetchState = .loading(requestKey)
        updateLoadingAndErrorStates()

        if lastRequestedCityID == nil {
            loadingPhase = .initial
        } else if lastRequestedCityID == city.id {
            loadingPhase = .refresh
        } else {
            loadingPhase = .citySwitch
        }
        lastRequestedCityID = city.id

        // Existing cached stops stay on screen while the new tiles load.
        updateStops()

        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }
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
                var updatedCache = self.cachedStopsByID
                for stop in fetchedStops {
                    updatedCache[stop.id] = stop
                }
                self.cachedStopsByID = updatedCache
                // Empty results still mark the tiles as fetched: an empty
                // viewport is authoritative for this session and must not
                // trigger a request on every settle.
                self.fetchedTiles.formUnion(tiles)
                self.inFlightTiles.removeAll()
                self.fetchState = .loaded(requestKey)
                self.loadingPhase = nil
                self.errorsByCity.removeValue(forKey: city.id)
                self.updateLoadingAndErrorStates()
                Logger.mapCache.debug("Fetch completed for \(city.id, privacy: .public): +\(fetchedStops.count, privacy: .public) stops (total cached: \(self.cachedStopsByID.count, privacy: .public)), +\(tiles.count, privacy: .public) tiles (total tiles: \(self.fetchedTiles.count, privacy: .public))")
                self.updateStops()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), generation == self.requestGeneration else {
                    Logger.mapCache.debug("Fetch error discarded for \(city.id, privacy: .public): cancelled or generation mismatch")
                    return
                }
                if self.selectedCity.id == city.id {
                    Logger.mapCache.error("Fetch failed for \(city.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.inFlightTiles.removeAll()
                    self.errorsByCity[city.id] = Self.userFacingMessage(for: error)
                    self.fetchState = .failed(requestKey)
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
        if case .loading = fetchState {
            fetchState = .idle
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
        cancelActiveFetch()
        inFlightTiles.removeAll()
        cachedStopsByID.removeAll()
        fetchedTiles.removeAll()
        errorsByCity.removeAll()
        updateLoadingAndErrorStates()
        updateStops()
    }

    // MARK: - Marker rendering

    private func updateStops() {
        guard areStopsVisible else {
            if !stops.isEmpty {
                stops = []
            }
            return
        }

        let region = cameraState.region
        let latitudeSpan = region.span.latitudeDelta
        let longitudeSpan = region.span.longitudeDelta
        guard latitudeSpan.isFinite, longitudeSpan.isFinite,
              latitudeSpan > 0, longitudeSpan > 0
        else { return }

        let minLat = region.center.latitude - latitudeSpan / 2
        let maxLat = region.center.latitude + latitudeSpan / 2
        let minLon = region.center.longitude - longitudeSpan / 2
        let maxLon = region.center.longitude + longitudeSpan / 2

        let visibleStops = cachedStopsByID.values.filter { stop in
            stop.latitude >= minLat && stop.latitude <= maxLat
                && stop.longitude >= minLon && stop.longitude <= maxLon
        }

        var renderedStops: [Stop]
        if visibleStops.count > Self.maxRenderedStops {
            renderedStops = Self.thinnedStops(visibleStops, region: region)
        } else {
            renderedStops = visibleStops.sorted { $0.id < $1.id }
        }

        // Always keep the currently selected stop visible if it falls within the viewport,
        // even if grid thinning would have dropped its cell.
        if let selectedStopID = selectedStopID,
           let selectedStop = cachedStopsByID[selectedStopID],
           selectedStop.latitude >= minLat && selectedStop.latitude <= maxLat,
           selectedStop.longitude >= minLon && selectedStop.longitude <= maxLon,
           !renderedStops.contains(where: { $0.id == selectedStopID }) {
            renderedStops.append(selectedStop)
            renderedStops.sort { $0.id < $1.id }
        }

        // Compare full values, not just IDs: a later viewport fetch can change
        // a stop's bearing, routes, or name while keeping the same identifier.
        // Camera-only changes still produce an equal array and are ignored.
        if renderedStops != stops {
            #if DEBUG
            Logger.mapCache.debug("Rendered stops updated: \(visibleStops.count, privacy: .public) visible in cache -> \(renderedStops.count, privacy: .public) rendered on map (ceiling: \(Self.maxRenderedStops, privacy: .public))")
            #endif
            stops = renderedStops
        }
    }

    /// Whether a stop lies inside the visible viewport.
    private static func contains(_ stop: Stop, in region: MKCoordinateRegion) -> Bool {
        let latitudeSpan = region.span.latitudeDelta
        let longitudeSpan = region.span.longitudeDelta
        guard latitudeSpan.isFinite, longitudeSpan.isFinite,
              latitudeSpan > 0, longitudeSpan > 0
        else { return false }
        let minLat = region.center.latitude - latitudeSpan / 2
        let maxLat = region.center.latitude + latitudeSpan / 2
        let minLon = region.center.longitude - longitudeSpan / 2
        let maxLon = region.center.longitude + longitudeSpan / 2
        return stop.latitude >= minLat && stop.latitude <= maxLat
            && stop.longitude >= minLon && stop.longitude <= maxLon
    }

    /// World-aligned spatial grid steps derived from the region span.
    /// Steps are quantized using ceil(log2(...)) to powers of two, ensuring that
    /// grid cell boundaries remain fixed in world coordinates during panning,
    /// and the total number of visible cells is strictly bounded by maxRenderedStops.
    private static func thinningSteps(for region: MKCoordinateRegion) -> (latStep: Double, lonStep: Double) {
        let latSpan = max(region.span.latitudeDelta, 1e-6)
        let lonSpan = max(region.span.longitudeDelta, 1e-6)
        // With at most 14 cells per axis, a viewport can intersect at most 15x15 = 225 cells <= 250.
        let targetLatStep = latSpan / 14.0
        let targetLonStep = lonSpan / 14.0
        let latStep = pow(2.0, ceil(log2(targetLatStep)))
        let lonStep = pow(2.0, ceil(log2(targetLonStep)))
        return (max(latStep, 1e-6), max(lonStep, 1e-6))
    }

    /// World-aligned cell index for a stop within the region.
    private static func cellIndex(
        for stop: Stop,
        in region: MKCoordinateRegion,
        latStep: Double,
        lonStep: Double
    ) -> Int? {
        guard contains(stop, in: region) else { return nil }
        let col = Int(floor(stop.longitude / lonStep))
        let row = Int(floor(stop.latitude / latStep))
        return (row &* 73856093) ^ (col &* 19349663)
    }

    /// Grid-based thinning: keep one deterministic representative per cell of
    /// a world-aligned spatial grid laid over the visible region.
    static func thinnedStops(_ rawStops: [Stop], region: MKCoordinateRegion?) -> [Stop] {
        guard let region = region else { return [] }
        let (latStep, lonStep) = thinningSteps(for: region)
        var buckets: [Int: Stop] = [:]
        for stop in rawStops {
            guard let cell = cellIndex(
                for: stop,
                in: region,
                latStep: latStep,
                lonStep: lonStep
            ) else { continue }
            if let current = buckets[cell] {
                // Deterministic pick so repainting does not flicker markers.
                if stop.id < current.id {
                    buckets[cell] = stop
                }
            } else {
                buckets[cell] = stop
            }
        }
        let sorted = buckets.values.sorted { $0.id < $1.id }
        if sorted.count > maxRenderedStops {
            return Array(sorted.prefix(maxRenderedStops))
        }
        return sorted
    }
}

