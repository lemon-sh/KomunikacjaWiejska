import CoreLocation
import Foundation
import MapKit
import Observation
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

    public var selectedCity: City {
        didSet {
            guard selectedCity != oldValue else { return }
            UserDefaults.standard.set(selectedCity.id, forKey: "lastSelectedCityId")
            selectedStopID = nil
            clearStopCache()
            repositionCameraForCurrentCity()
            loadStopsForSelectedCity()
        }
    }

    public var cameraPosition: MapCameraPosition
    public var cameraState: CameraState
    /// Markers currently rendered on the map. This is the visible, thinned
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
    /// compact points. Distance-based so it is independent of each city's
    /// default span: every normal city (span ≤ 0.15°) loads fully zoomed
    /// markers, while the countrywide PKP view starts compact.
    public let compactDisplayDistanceThreshold: Double = 20_000

    /// Whether the camera is far enough that stops should be displayed as smaller points.
    public var isCompactDisplayMode: Bool {
        return currentDistance > compactDisplayDistanceThreshold
    }

    /// Whether the map is currently pitched in 3D (pitch > 1.0 degree)
    public var isPitched3D: Bool {
        return currentPitch > 1.0
    }

    /// Hard ceiling on markers rendered at once; extra stops are thinned to
    /// one representative per grid cell (see `thinnedStops`).
    static let maxRenderedStops = 250
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
        guard !visibleTiles.isEmpty else { return .invalid }
        let missingTiles = visibleTiles.filter { !isTileCovered($0) }
        guard !missingTiles.isEmpty else { return .cached }
        guard let bbox = MapTileGrid.boundingBox(covering: missingTiles) else {
            return .invalid
        }
        return .fetch(bbox: bbox, tiles: missingTiles)
    }

    /// A tile is covered by itself or any of its ancestors: a coarser fetch
    /// already returned every stop inside the finer tile. Descendants are not
    /// consulted; zooming out of a deeply zoomed area fetches the coarser
    /// tiles once, after which zooming back in is free.
    private func isTileCovered(_ tile: MapTile) -> Bool {
        var candidate: MapTile? = tile
        while let current = candidate {
            if fetchedTiles.contains(current) {
                return true
            }
            candidate = current.parent
        }
        return false
    }

    private func startFetch(city: City, bbox: BoundingBox, tiles: Set<MapTile>) {
        let key = "\(city.id):\(bbox.queryValue)"
        guard fetchState != .loading(cityKey: key) else { return }

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
                guard !Task.isCancelled, generation == self.requestGeneration else { return }
                guard self.selectedCity.id == city.id else { return }
                for stop in fetchedStops {
                    self.cachedStopsByID[stop.id] = stop
                }
                // Empty results still mark the tiles as fetched: an empty
                // viewport is authoritative for this session and must not
                // trigger a request on every settle.
                self.fetchedTiles.formUnion(tiles)
                self.fetchState = .loaded(cityKey: key)
                self.loadingPhase = nil
                self.updateStops()
            } catch {
                guard !Task.isCancelled, generation == self.requestGeneration else { return }
                if self.selectedCity.id == city.id {
                    self.errorsByCity[city.id] = Self.userFacingMessage(for: error)
                    self.fetchState = .failed(cityKey: key)
                    self.loadingPhase = nil
                }
            }
        }
    }

    private func cancelActiveFetch() {
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
        debounceTask?.cancel()
        debounceTask = nil
        cancelActiveFetch()
        cachedStopsByID.removeAll()
        fetchedTiles.removeAll()
        updateStops()
    }

    // MARK: - Marker rendering (P2-2)

    private func updateStops() {
        let region = cameraState.region
        let visibleStops = cachedStopsByID.values.filter { Self.contains($0, in: region) }

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
           Self.contains(selectedStop, in: region),
           !renderedStops.contains(where: { $0.id == selectedStopID }) {
            renderedStops.append(selectedStop)
            renderedStops.sort { $0.id < $1.id }
        }

        // Compare full values, not just IDs: a later viewport fetch can change
        // a stop's bearing, routes, or name while keeping the same identifier.
        // Camera-only changes still produce an equal array and are ignored.
        if renderedStops != stops {
            stops = renderedStops
        }
    }

    /// Whether a stop lies inside the visible viewport. The cache is
    /// city-wide, so this filter is required even when no thinning runs.
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

    /// Grid-based thinning: keep one deterministic representative per cell of
    /// a grid laid over the visible region.
    static func thinnedStops(_ rawStops: [Stop], region: MKCoordinateRegion?) -> [Stop] {
        guard let region = region else { return [] }
        let grid = thinningGrid()
        var buckets: [Int: Stop] = [:]
        for stop in rawStops {
            guard let cell = cellIndex(
                for: stop,
                in: region,
                grid: grid
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
        return buckets.values.sorted { $0.id < $1.id }
    }

    private struct ThinningGrid {
        let columns: Int
        let rows: Int
    }

    /// Fixed grid sized to `maxRenderedStops`. It must not be derived from the
    /// stop count: `sqrt(count / cap)` produces very few cells for dense
    /// viewports (e.g. a 2×2 grid for 1,000 stops), discarding nearly every
    /// marker. 15×16 = 240 slots stays under the cap.
    private static func thinningGrid() -> ThinningGrid {
        let columns = max(2, Int(Double(maxRenderedStops).squareRoot()))
        let rows = max(2, maxRenderedStops / columns)
        return ThinningGrid(columns: columns, rows: rows)
    }

    private static func cellIndex(
        for stop: Stop,
        in region: MKCoordinateRegion,
        grid: ThinningGrid
    ) -> Int? {
        let latitudeSpan = max(region.span.latitudeDelta, 1e-6)
        let longitudeSpan = max(region.span.longitudeDelta, 1e-6)
        let dx = (stop.longitude - region.center.longitude) / longitudeSpan
        let dy = (stop.latitude - region.center.latitude) / latitudeSpan
        guard abs(dx) <= 0.5, abs(dy) <= 0.5 else { return nil }  // outside viewport
        let column = clampCell(Int((dx + 0.5) * Double(grid.columns)), limit: grid.columns)
        let row = clampCell(Int((dy + 0.5) * Double(grid.rows)), limit: grid.rows)
        return row * grid.columns + column
    }

    private static func clampCell(_ value: Int, limit: Int) -> Int {
        min(max(value, 0), limit - 1)
    }
}

