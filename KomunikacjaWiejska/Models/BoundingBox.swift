import CoreLocation
import Foundation
import MapKit

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

    init?(_ region: MKCoordinateRegion) {
        let latSpan = region.span.latitudeDelta
        let lonSpan = region.span.longitudeDelta
        guard latSpan.isFinite, lonSpan.isFinite, latSpan > 0, lonSpan > 0 else { return nil }
        self.minLon = region.center.longitude - lonSpan / 2
        self.minLat = region.center.latitude - latSpan / 2
        self.maxLon = region.center.longitude + lonSpan / 2
        self.maxLat = region.center.latitude + latSpan / 2
    }

    init?(region: MKCoordinateRegion) {
        self.init(region)
    }

    var queryValue: String {
        String(format: "%.6f,%.6f,%.6f,%.6f", minLon, minLat, maxLon, maxLat)
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLat && latitude <= maxLat && longitude >= minLon && longitude <= maxLon
    }

    func contains(_ other: BoundingBox) -> Bool {
        other.minLat >= minLat && other.maxLat <= maxLat && other.minLon >= minLon && other.maxLon <= maxLon
    }

    var clamped: BoundingBox {
        BoundingBox(
            minLon: max(minLon, -180),
            minLat: max(minLat, -90),
            maxLon: min(maxLon, 180),
            maxLat: min(maxLat, 90)
        )
    }
}
