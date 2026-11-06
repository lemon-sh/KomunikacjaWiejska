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
public enum MapMode: String, CaseIterable, Identifiable {
    case explore = "Explore"
    case satellite = "Satellite"

    public var id: String { rawValue }

    /// Localized label. `rawValue` stays a stable, locale-independent
    /// identifier (persisted state, tests, analytics); never render it.
    public var displayName: String {
        switch self {
        case .explore:
            return String(localized: "mapMode.explore")
        case .satellite:
            return String(localized: "mapMode.satellite")
        }
    }

    public var mapStyle: MapStyle {
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
public enum StopLoadingPhase: Equatable, Sendable {
    case initial
    case refresh
    case citySwitch
}

@Observable
@MainActor
public final class MapViewModel {
    /// Camera-derived metrics grouped into one tracked value so a camera
    /// gesture updates a single observation instead of four (and so
    /// derived values like compact mode and the rendered marker set
    /// re-evaluate only when the camera actually changed).
    public struct CameraState: Equatable {
        public var region: MKCoordinateRegion
        public var heading: Double
        public var pitch: Double
        public var distance: Double
        public var center: CLLocationCoordinate2D

        public init(
            region: MKCoordinateRegion,
            heading: Double = 0,
            pitch: Double = 0,
            distance: Double = 0,
            center: CLLocationCoordinate2D
        ) {
            self.region = region
            self.heading = heading
            self.pitch = pitch
            self.distance = distance
            self.center = center
        }

        public static func == (lhs: CameraState, rhs: CameraState) -> Bool {
            lhs.heading == rhs.heading
                && lhs.pitch == rhs.pitch
                && lhs.distance == rhs.distance
                && lhs.center.isApproximatelyEqual(to: rhs.center)
                && lhs.region.center.isApproximatelyEqual(to: rhs.region.center)
                && abs(lhs.region.span.latitudeDelta - rhs.region.span.latitudeDelta) < 1e-7
                && abs(lhs.region.span.longitudeDelta - rhs.region.span.longitudeDelta) < 1e-7
        }
    }

    @ObservationIgnored private var shouldRepositionOnCityChange = true

    public var selectedCity: City {
        didSet {
            guard selectedCity != oldValue else { return }
            UserDefaults.standard.set(selectedCity.id, forKey: "lastSelectedCityId")
            selectedStopID = nil
            clearStopCache()
            if shouldRepositionOnCityChange {
                repositionCameraForCurrentCity()
            }
            suggestedCity = nil
            loadStopsForSelectedCity()
        }
    }

    /// City suggested to the user when viewing an area outside the current city's territory.
    public private(set) var suggestedCity: City?
    /// City ID whose suggestion was dismissed by the user to avoid repeated prompting.
    public private(set) var dismissedCityID: String?

    public var cameraPosition: MapCameraPosition
    public var cameraState: CameraState
    /// Markers currently rendered on the map. This is the visible
    /// view of the session stop cache.
    public private(set) var stops: [Stop] = []
    /// Marker selection source of truth: the map writes the tagged stop ID,
    /// the detail sheet is derived from it. Identify by ID instead of the full
    /// `Stop` value so selection compares a string, not routes/entances.
    public var selectedStopID: String? {
        didSet {
            guard selectedStopID != oldValue else { return }
            updateStops()
        }
    }
    public var isShowingCityPicker: Bool = false
    public var selectedMapMode: MapMode = .explore
    public var isShowingMapModes: Bool = false
    public var isTrackingUser: Bool = false

    public var currentHeading: Double {
        get { cameraState.heading }
        set { cameraState.heading = newValue }
    }

    public var currentPitch: Double {
        get { cameraState.pitch }
        set { cameraState.pitch = newValue }
    }

    public var currentDistance: Double {
        get { cameraState.distance }
        set { cameraState.distance = newValue }
    }

    public var currentCenter: CLLocationCoordinate2D {
        get { cameraState.center }
        set { cameraState.center = newValue }
    }

    public var visibleRegion: MKCoordinateRegion? {
        get { cameraState.region }
        set {
            if let region = newValue {
                cameraState.region = region
            }
        }
    }

    /// Whether the currently selected city's viewport has a request in flight.
    public var isLoading: Bool {
        if case .loading(let key) = fetchState, key.hasPrefix("\(selectedCity.id):") {
            return true
        }
        return false
    }

    /// The reason for the current load, or `nil` when nothing is in flight.
    public private(set) var loadingPhase: StopLoadingPhase?

    /// Failure message for the currently selected city, if any. Errors are
    /// tracked per city so a failed fetch for city A never surfaces while
    /// viewing city B.
    public var errorMessage: String? {
        errorsByCity[selectedCity.id]
    }

    /// The stop currently selected, looked up by `selectedStopID`. Derived —
    /// never set this; write to `selectedStopID` instead.
    public var selectedStop: Stop? {
        guard let selectedStopID = selectedStopID else { return nil }
        return cachedStopsByID[selectedStopID]
    }

    /// Looks up a stop in the session cache by its identifier.
    public func cachedStop(for id: String) -> Stop? {
        cachedStopsByID[id]
    }

    /// Cycle a city's stop fetch can be in. Guarantees one in-flight request
    /// per viewport and makes loading idempotent.
    private enum FetchState: Equatable {
        case idle
        case loading(cityKey: String)
        case loaded(cityKey: String)
        case failed(cityKey: String)
    }

    private var fetchState: FetchState = .idle

    /// Camera distance (in metres) above which stops are displayed as smaller
    /// compact points.
    public let compactDisplayDistanceThreshold: Double = 6_000

    /// Camera distance (in metres) above which stops are no longer displayed at all.
    public let stopVisibilityDistanceThreshold: Double = 12_000

    /// Whether the camera is far enough that stops should be displayed as smaller points.
    public var isCompactDisplayMode: Bool {
        return currentDistance > compactDisplayDistanceThreshold
    }

    /// Whether stops should be displayed on the map.
    public var areStopsVisible: Bool {
        return currentDistance <= stopVisibilityDistanceThreshold
    }

    /// Keys for camera persistence in non-volatile storage.
    public static let savedCameraLatitudeKey = "savedCameraLatitude"
    public static let savedCameraLongitudeKey = "savedCameraLongitude"
    public static let savedCameraDistanceKey = "savedCameraDistance"

    /// Whether the map is currently pitched in 3D (pitch > 1.0 degree)
    public var isPitched3D: Bool {
        return currentPitch > 1.0
    }

    /// Debounce applied to fetches triggered by camera movement.
    private static let cameraFetchDebounce: Duration = .milliseconds(350)

    private let apiClient: any StopsProviding
    // `nonisolated(unsafe)`: only mutated from `@MainActor` methods, read from
    // `deinit` (nonisolated by definition). `Task` is `Sendable`, so cancelling
    // from any context is safe; the reference itself is never read concurrently.
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var debounceTask: Task<Void, Never>?
    /// Session-only stop cache for the selected city. Never persisted, and
    /// cleared on every city switch. Stop data is treated as stable for the
    /// lifetime of the app process, so entries never expire.
    private var cachedStopsByID: [String: Stop] = [:]
    /// Tiles whose bbox has been fetched successfully in this session. A tile
    /// also covers all of its descendants, so zooming in needs no new data.
    private var fetchedTiles: Set<MapTile> = []
    private var errorsByCity: [String: String] = [:]
    /// Generation token guarding against stale responses: each fetch gets a
    /// fresh token, and a response only applies if it still matches.
    private var requestGeneration = UUID()
    /// City of the last request, even when no data has arrived yet. Lets the
    /// loading phase distinguish a switch from a cold start.
    private var lastRequestedCityID: String?

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

        var restoredCamera: (center: CLLocationCoordinate2D, distance: Double)?
        if initialCity == nil,
           let savedLat = UserDefaults.standard.object(forKey: Self.savedCameraLatitudeKey) as? Double,
           let savedLon = UserDefaults.standard.object(forKey: Self.savedCameraLongitudeKey) as? Double,
           let savedDist = UserDefaults.standard.object(forKey: Self.savedCameraDistanceKey) as? Double,
           savedLat.isFinite, savedLon.isFinite, savedDist.isFinite, savedDist > 0,
           (-90.0...90.0).contains(savedLat), (-180.0...180.0).contains(savedLon) {
            let savedCoord = CLLocationCoordinate2D(latitude: savedLat, longitude: savedLon)
            let isWithinCityBounds: Bool
            if chosenCity.id == "pkp" {
                isWithinCityBounds = true
            } else {
                let cityLocation = CLLocation(latitude: chosenCity.coordinate.latitude, longitude: chosenCity.coordinate.longitude)
                let savedLocation = CLLocation(latitude: savedCoord.latitude, longitude: savedCoord.longitude)
                isWithinCityBounds = savedLocation.distance(from: cityLocation) <= chosenCity.coverageRadiusMeters
            }
            if isWithinCityBounds {
                restoredCamera = (center: savedCoord, distance: savedDist)
            }
        }

        if let restored = restoredCamera {
            let delta = max(0.001, min(180.0, restored.distance / 111_000))
            let region = MKCoordinateRegion(
                center: restored.center,
                span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
            )
            self.cameraState = CameraState(
                region: region,
                distance: restored.distance,
                center: restored.center
            )
            self.cameraPosition = .camera(MapCamera(
                centerCoordinate: restored.center,
                distance: restored.distance,
                heading: 0,
                pitch: 0
            ))
        } else {
            let initialRegion = MKCoordinateRegion(
                center: chosenCity.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: chosenCity.defaultLatitudeDelta,
                    longitudeDelta: chosenCity.defaultLongitudeDelta
                )
            )
            self.cameraState = CameraState(
                region: initialRegion,
                distance: Self.approximateDistance(for: initialRegion),
                center: chosenCity.coordinate
            )
            self.cameraPosition = .region(initialRegion)
        }
    }

    /// Persists current camera center and zoom distance to non-volatile storage.
    public func saveCameraPosition() {
        UserDefaults.standard.set(currentCenter.latitude, forKey: Self.savedCameraLatitudeKey)
        UserDefaults.standard.set(currentCenter.longitude, forKey: Self.savedCameraLongitudeKey)
        UserDefaults.standard.set(currentDistance, forKey: Self.savedCameraDistanceKey)
    }

    deinit {
        activeFetchTask?.cancel()
        debounceTask?.cancel()
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
        region.span.latitudeDelta * 111_000
    }

    public func handleCameraChange(to context: MapCameraUpdateContext) {
        let newState = CameraState(
            region: context.region,
            heading: context.camera.heading,
            pitch: context.camera.pitch,
            distance: context.camera.distance,
            center: context.camera.centerCoordinate
        )
        guard newState != cameraState else {
            // Still evaluate tracking release; nothing to observe otherwise.
            releaseTrackingIfRoaming(to: context.camera.centerCoordinate)
            return
        }
        cameraState = newState
        updateStops()
        releaseTrackingIfRoaming(to: context.camera.centerCoordinate)
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
            cameraState.center = coordinate
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
            cameraState.pitch = 0
        }
    }

    // MARK: - Region Suggestion

    /// Evaluates whether the current camera viewport belongs to a different transit network,
    /// updating `suggestedCity`.
    public func updateRegionSuggestion() {
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
    public static func detectSuggestedCity(
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
        if currentCity.id != "pkp" {
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
    public func selectCity(_ city: City, repositionCamera: Bool = true) {
        guard city != selectedCity else { return }
        shouldRepositionOnCityChange = repositionCamera
        selectedCity = city
        shouldRepositionOnCityChange = true
    }

    /// Switches the active city to the currently suggested city without moving the camera,
    /// so the user retains their exact viewing position.
    public func switchToSuggestedCity() {
        guard let city = suggestedCity else { return }
        selectCity(city, repositionCamera: false)
    }

    /// Dismisses the current region switch suggestion.
    public func dismissSuggestedCity() {
        if let currentSuggestion = suggestedCity {
            dismissedCityID = currentSuggestion.id
            suggestedCity = nil
        }
    }

    // MARK: - Stop fetching (tiled viewport coverage, D1-A)

    /// Why the current viewport does or does not need a request.
    private enum ViewportLoad {
        case cached
        case fetch(bbox: BoundingBox, tiles: Set<MapTile>)
        case invalid
    }

    /// Loads stops for the selected city's current viewport. Idempotent while
    /// a request for the same area is in flight or every required tile is
    /// already cached.
    public func loadStopsForSelectedCity() {
        debounceTask?.cancel()
        debounceTask = nil
        fetchCurrentViewport()
    }

    // MARK: - Scene phase (P2-5)

    /// Cancels in-flight network work when the scene backgrounds. The session
    /// cache is kept in memory so returning to the foreground stays instant.
    public func pauseForBackground() {
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
            fetchState = .loaded(cityKey: "\(city.id):tiles")
            errorsByCity[city.id] = nil
            loadingPhase = nil
            updateStops()
        case .fetch(let bbox, let tiles):
            startFetch(city: city, bbox: bbox, tiles: tiles)
        case .invalid:
            cancelActiveFetch()
        }
    }

    /// Debounces fetches triggered by `.onEnd` camera changes (P1/P2-1).
    private func scheduleViewportFetch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: Self.cameraFetchDebounce)
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
            #if DEBUG
            Logger.mapCache.debug("Load decision: invalid region (visible tiles is empty)")
            #endif
            return .invalid
        }
        let missingTiles = visibleTiles.filter { !isTileCovered($0) }
        guard !missingTiles.isEmpty else {
            #if DEBUG
            let zoom = visibleTiles.first?.zoom ?? 0
            Logger.mapCache.debug("Cache HIT: all \(visibleTiles.count, privacy: .public) visible tiles at zoom \(zoom, privacy: .public) covered. Cached stops: \(self.cachedStopsByID.count, privacy: .public)")
            #endif
            return .cached
        }
        guard let bbox = MapTileGrid.boundingBox(covering: missingTiles) else {
            #if DEBUG
            Logger.mapCache.debug("Load decision: failed to create bounding box for \(missingTiles.count, privacy: .public) missing tiles")
            #endif
            return .invalid
        }
        #if DEBUG
        let zoom = visibleTiles.first?.zoom ?? 0
        Logger.mapCache.debug("Cache MISS: \(missingTiles.count, privacy: .public) of \(visibleTiles.count, privacy: .public) visible tiles missing at zoom \(zoom, privacy: .public). Querying bbox: \(bbox.queryValue, privacy: .public)")
        #endif
        return .fetch(bbox: bbox, tiles: missingTiles)
    }

    /// A tile is covered if it has been fetched successfully in this session.
    /// With fixed-size Zoom 12 tiles, there is no ancestor hierarchy.
    private func isTileCovered(_ tile: MapTile) -> Bool {
        fetchedTiles.contains(tile)
    }

    private func startFetch(city: City, bbox: BoundingBox, tiles: Set<MapTile>) {
        let key = "\(city.id):\(bbox.queryValue)"
        guard fetchState != .loading(cityKey: key) else {
            #if DEBUG
            Logger.mapCache.debug("Start fetch skipped: already in flight for \(key, privacy: .public)")
            #endif
            return
        }

        #if DEBUG
        Logger.mapCache.debug("Starting fetch for city \(city.id, privacy: .public), bbox: \(bbox.queryValue, privacy: .public), missing tiles: \(tiles.count, privacy: .public)")
        #endif

        activeFetchTask?.cancel()
        debounceTask?.cancel()
        debounceTask = nil
        requestGeneration = UUID()
        let generation = requestGeneration
        errorsByCity[city.id] = nil
        fetchState = .loading(cityKey: key)

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
                for stop in fetchedStops {
                    self.cachedStopsByID[stop.id] = stop
                }
                // Empty results still mark the tiles as fetched: an empty
                // viewport is authoritative for this session and must not
                // trigger a request on every settle.
                self.fetchedTiles.formUnion(tiles)
                self.fetchState = .loaded(cityKey: key)
                self.loadingPhase = nil
                #if DEBUG
                Logger.mapCache.debug("Fetch completed for \(city.id, privacy: .public): +\(fetchedStops.count, privacy: .public) stops (total cached: \(self.cachedStopsByID.count, privacy: .public)), +\(tiles.count, privacy: .public) tiles (total tiles: \(self.fetchedTiles.count, privacy: .public))")
                #endif
                self.updateStops()
            } catch {
                guard !Task.isCancelled, generation == self.requestGeneration else {
                    #if DEBUG
                    Logger.mapCache.debug("Fetch error discarded for \(city.id, privacy: .public): cancelled or generation mismatch")
                    #endif
                    return
                }
                if self.selectedCity.id == city.id {
                    #if DEBUG
                    Logger.mapCache.error("Fetch failed for \(city.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    #endif
                    self.errorsByCity[city.id] = Self.userFacingMessage(for: error)
                    self.fetchState = .failed(cityKey: key)
                    self.loadingPhase = nil
                }
            }
        }
    }

    private func cancelActiveFetch() {
        if activeFetchTask != nil {
            #if DEBUG
            Logger.mapCache.debug("Cancelling active fetch for city \(self.selectedCity.id, privacy: .public)")
            #endif
        }
        activeFetchTask?.cancel()
        activeFetchTask = nil
        // Invalidate the generation so a task already past its guard writes
        // nothing after cancellation.
        requestGeneration = UUID()
        loadingPhase = nil
        if case .loading = fetchState {
            fetchState = .idle
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
        cachedStopsByID.removeAll()
        fetchedTiles.removeAll()
        updateStops()
    }

    // MARK: - Marker rendering (P2-2)

    private func updateStops() {
        guard areStopsVisible else {
            if !stops.isEmpty {
                stops = []
            }
            return
        }

        let region = cameraState.region
        let renderedStops = cachedStopsByID.values
            .filter { Self.contains($0, in: region) }
            .sorted { $0.id < $1.id }

        // Compare full values, not just IDs: a later viewport fetch can change
        // a stop's bearing, routes, or name while keeping the same identifier.
        // Camera-only changes still produce an equal array and are ignored.
        if renderedStops != stops {
            #if DEBUG
            Logger.mapCache.debug("Rendered stops updated: \(renderedStops.count, privacy: .public) rendered on map")
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
        let dx = (stop.longitude - region.center.longitude) / longitudeSpan
        let dy = (stop.latitude - region.center.latitude) / latitudeSpan
        return abs(dx) <= 0.5 && abs(dy) <= 0.5
    }
}

