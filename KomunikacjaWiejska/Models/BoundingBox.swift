import Foundation

/// Geographic bounding box defining min/max longitude and latitude.
/// Explicitly nonisolated and Sendable for cross-actor transfer.
public nonisolated struct BoundingBox: Hashable, Sendable {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    public var queryValue: String {
        String(format: "%.6f,%.6f,%.6f,%.6f", minLon, minLat, maxLon, maxLat)
    }
}
