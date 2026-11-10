import Foundation

nonisolated enum MapConstants {
    /// Approximate metres per degree of latitude (~111 km).
    static let metresPerDegreeLatitude: Double = 111_000

    /// Debounce applied to viewport stops fetches triggered by camera movements.
    static let cameraFetchDebounce: Duration = .milliseconds(350)

    /// Camera distance (in metres) above which stops are no longer displayed at all.
    static let stopVisibilityDistanceThreshold: Double = 3_000

    /// Camera distance (in metres) above which stop name labels are hidden.
    static let stopTitleVisibilityDistanceThreshold: Double = 500

    /// Camera distance (in metres) above which vehicles are hidden and polling stops.
    static let vehicleVisibilityDistanceThreshold: Double = 10_000

    /// Camera distance (in metres) above which vehicles switch to compact dot display mode.
    static let vehicleCompactDistanceThreshold: Double = 2_000

    /// Polling and TTL interval in seconds for live vehicle positions.
    static let vehicleTTL: TimeInterval = 15.0

    /// Hard ceiling on vehicle markers rendered at once; extra vehicles are thinned to
    /// one representative per grid cell (see `thinnedVehicles`).
    static let maxRenderedVehicles: Int = 150

    /// Margin expansion multiplier for buffering the visible viewport (e.g. 50% extra on each dimension).
    static let viewportBufferFactor: Double = 1.50

    /// Maximum zoom ratio change allowed before re-evaluating viewport bounds.
    static let zoomChangeRatioThreshold: Double = 0.20
}

