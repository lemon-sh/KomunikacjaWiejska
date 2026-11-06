import Foundation

/// Geographic bounding box defining min/max longitude and latitude.
/// Explicitly nonisolated and Sendable for cross-actor transfer.
nonisolated struct BoundingBox: Hashable, Sendable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    var queryValue: String {
        String(format: "%.6f,%.6f,%.6f,%.6f", minLon, minLat, maxLon, maxLat)
    }
}
