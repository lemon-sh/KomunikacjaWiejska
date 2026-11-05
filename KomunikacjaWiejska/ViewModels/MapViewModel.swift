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
/// from a manual refresh or a city switch without inferring it from timing.
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
            repositionCameraForCurrentCity()
            loadStopsForSelectedCity()
        }
    }

    public var cameraPosition: MapCameraPosition
    public var cameraState: CameraState
    /// Markers currently rendered on the map. This is the thinned view of the
    /// fetched stop set; the full fetched set is kept off-screen.
    public private(set) var stops: [Stop] = []
    /// Marker selection source of truth: the map writes the tagged stop ID,
    /// the detail sheet is derived from it. Identify by ID instead of the full
    /// `Stop` value so selection compares a string, not routes/entances.
    public var selectedStopID: String?
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
        return fetchedStops.first(where: { $0.id == selectedStopID })
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
    public let compactDisplayDistanceThreshold: Double = 50_000

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
    /// How long a cached viewport snapshot is served without refetching.
    private static let stopsCacheTTL: TimeInterval = 600
    /// Maximum number of cached viewport snapshots kept in memory (LRU).
    private static let stopsCacheCapacity = 8

    private struct CacheSnapshot {
        let stops: [Stop]
        let cachedAt: Date
    }

    private let apiClient: any StopsProviding
    // `nonisolated(unsafe)`: only mutated from `@MainActor` methods, read from
    // `deinit` (nonisolated by definition). `Task` is `Sendable`, so cancelling
    // from any context is safe; the reference itself is never read concurrently.
    @ObservationIgnored private nonisolated(unsafe) var activeFetchTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var debounceTask: Task<Void, Never>?
    private var viewportCache: [String: CacheSnapshot] = [:]
    private var cacheAccessOrder: [String] = []
    private var errorsByCity: [String: String] = [:]
    /// Generation token guarding against stale responses: each fetch gets a
    /// fresh token, and a response only applies if it still matches.
    private var requestGeneration = UUID()
    /// Un-thinned results for the viewport currently displayed.
    private var fetchedStops: [Stop] = []
    /// Cache key of the data currently on screen, if any.
    private var displayedKey: String?
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
            distance: 15_000,
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
        cameraState = CameraState(region: newRegion, distance: currentDistance, center: selectedCity.coordinate)
        isTrackingUser = false
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

    // MARK: - Stop fetching (viewport bbox strategy, D1-A)

    /// Loads stops for the selected city's current viewport. Idempotent while
    /// a request for the same viewport is in flight or a fresh enough cached
    /// snapshot exists; manual refresh is available via
    /// `refreshStopsForSelectedCity()`.
    public func loadStopsForSelectedCity() {
        debounceTask?.cancel()
        fetchCurrentViewport()
    }

    /// Forces a fresh fetch of the current viewport, discarding cached data.
    public func refreshStopsForSelectedCity() {
        invalidateViewportCache(cityID: selectedCity.id)
        loadStopsForSelectedCity()
    }

    // MARK: - Scene phase (P2-5)

    /// Cancels in-flight network work when the scene backgrounds.
    public func pauseForBackground() {
        activeFetchTask?.cancel()
        debounceTask?.cancel()
        // Invalidate the generation so a task that already past its guard
        // writes nothing after resume.
        requestGeneration = UUID()
        loadingPhase = nil
        if case .loading = fetchState {
            fetchState = .idle
        }
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
        guard let bbox = BoundingBox(region: cameraState.region) else {
            loadingPhase = nil
            return
        }
        let key = Self.cacheKey(city: city, bbox: bbox)

        // A fresh snapshot for exactly this viewport needs no network at all.
        if let freshSnapshot = freshSnapshot(key: key) {
            fetchState = .loaded(cityKey: key)
            loadingPhase = nil
            // A cached viewport is a successful load; do not keep showing an
            // error from an earlier failed attempt.
            errorsByCity[city.id] = nil
            if displayedKey != key {
                display(freshSnapshot.stops, forKey: key)
            }
            return
        }

        startFetch(city: city, bbox: bbox, key: key)
    }

    /// Debounces fetches triggered by `.onEnd` camera changes (P1/P2-1).
    private func scheduleViewportFetch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: Self.cameraFetchDebounce)
            guard !Task.isCancelled else { return }
            let city = self.selectedCity
            guard let bbox = BoundingBox(region: self.cameraState.region) else { return }
            let key = Self.cacheKey(city: city, bbox: bbox)
            if case .loading(let loadingKey) = self.fetchState, loadingKey == key { return }
            if case .loaded(let loadedKey) = self.fetchState, loadedKey == key, self.freshSnapshot(key: key) != nil {
                return
            }
            self.startFetch(city: city, bbox: bbox, key: key)
        }
    }

    private func startFetch(city: City, bbox: BoundingBox, key: String) {
        guard fetchState != .loading(cityKey: key) else { return }

        activeFetchTask?.cancel()
        debounceTask?.cancel()
        requestGeneration = UUID()
        let generation = requestGeneration
        errorsByCity[city.id] = nil
        fetchState = .loading(cityKey: key)

        // Classify the load before any displayed data is cleared. Fall back to
        // the last requested city when the previous request has not produced
        // data yet (e.g. switching while the first city is still loading).
        let previousCityID = displayedKey
            .map { String($0.prefix(while: { $0 != ":" })) } ?? lastRequestedCityID
        if previousCityID == nil {
            loadingPhase = .initial
        } else if previousCityID == city.id {
            loadingPhase = .refresh
        } else {
            loadingPhase = .citySwitch
        }
        lastRequestedCityID = city.id

        // Keep previously fetched results on screen while refreshing the same
        // viewport; for a new viewport (pan/zoom/city switch) drop the stale
        // set first so old data never lingers.
        if displayedKey != key {
            if let snapshot = viewportCache[key] {
                display(snapshot.stops, forKey: key)
            } else {
                clearDisplayedData()
            }
        }

        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let fetchedStops = try await self.apiClient.fetchStops(city: city.id, bbox: bbox)
                guard !Task.isCancelled, generation == self.requestGeneration else { return }
                // Empty or partial results must not poison the cache.
                if !fetchedStops.isEmpty {
                    self.storeInCache(fetchedStops, key: key)
                }
                if self.selectedCity.id == city.id {
                    self.display(fetchedStops, forKey: key)
                    self.fetchState = .loaded(cityKey: key)
                    self.loadingPhase = nil
                }
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

    // MARK: - Viewport cache (bounded, TTL, LRU — P2-3)

    private func storeInCache(_ stops: [Stop], key: String) {
        viewportCache[key] = CacheSnapshot(stops: stops, cachedAt: Date.now)
        // Refresh LRU order.
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(key)
        while cacheAccessOrder.count > Self.stopsCacheCapacity {
            let evicted = cacheAccessOrder.removeFirst()
            viewportCache.removeValue(forKey: evicted)
        }
    }

    private func freshSnapshot(key: String) -> CacheSnapshot? {
        guard let snapshot = viewportCache[key],
              Date.now.timeIntervalSince(snapshot.cachedAt) < Self.stopsCacheTTL
        else { return nil }
        // LRU touch.
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
            cacheAccessOrder.append(key)
        }
        return snapshot
    }

    private func invalidateViewportCache(cityID: String) {
        let prefix = "\(cityID):"
        for key in cacheAccessOrder where key.hasPrefix(prefix) {
            viewportCache.removeValue(forKey: key)
        }
        cacheAccessOrder.removeAll(where: { $0.hasPrefix(prefix) })
    }

    /// Cache key is the exact six-decimal viewport sent to the API. Coarser
    /// rounding (e.g. 0.01°) would let two different viewports share an entry
    /// and silently omit stops at high zoom; the debounce already prevents
    /// request storms from tiny camera nudges.
    private static func cacheKey(city: City, bbox: BoundingBox) -> String {
        "\(city.id):\(bbox.queryValue)"
    }

    // MARK: - Marker thinning (P2-2)
    private func display(_ stops: [Stop], forKey key: String) {
        fetchedStops = stops
        displayedKey = key
        updateStops()
    }

    private func clearDisplayedData() {
        fetchedStops = []
        displayedKey = nil
        updateStops()
    }

    private func updateStops() {
        var thinnedStops = fetchedStops
        if thinnedStops.count > Self.maxRenderedStops {
            thinnedStops = Self.thinnedStops(fetchedStops, region: cameraState.region)
        }
        // Compare full values, not just IDs: a manual refresh can change a
        // stop's bearing, routes, or name while keeping the same identifier.
        // Camera-only changes still produce an equal array and are ignored.
        if thinnedStops != stops {
            stops = thinnedStops
        }
    }

    /// Grid-based thinning: keep one deterministic representative per cell of
    /// a square grid laid over the visible region.
    static func thinnedStops(_ rawStops: [Stop], region: MKCoordinateRegion?) -> [Stop] {
        guard let region = region else { return [] }
        let gridCells = gridDimensions(stopCount: rawStops.count)
        var buckets: [Int: Stop] = [:]
        for stop in rawStops {
            guard let cell = cellIndex(
                for: stop,
                in: region,
                gridCells: gridCells
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

    private static func gridDimensions(stopCount: Int) -> Int {
        let raw = sqrt(Double(stopCount) / Double(maxRenderedStops))
        return max(2, Int(ceil(raw)))
    }

    private static func cellIndex(
        for stop: Stop,
        in region: MKCoordinateRegion,
        gridCells: Int
    ) -> Int? {
        let latitudeSpan = max(region.span.latitudeDelta, 1e-6)
        let longitudeSpan = max(region.span.longitudeDelta, 1e-6)
        let dx = (stop.longitude - region.center.longitude) / longitudeSpan
        let dy = (stop.latitude - region.center.latitude) / latitudeSpan
        guard abs(dx) <= 0.5, abs(dy) <= 0.5 else { return nil }  // outside viewport
        let column = clampCell(Int((dx + 0.5) * Double(gridCells)), gridCells: gridCells)
        let row = clampCell(Int((dy + 0.5) * Double(gridCells)), gridCells: gridCells)
        return row * gridCells + column
    }

    private static func clampCell(_ value: Int, gridCells: Int) -> Int {
        min(max(value, 0), gridCells - 1)
    }
}

