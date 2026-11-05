import CoreLocation
import Foundation
import MapKit

public struct BoundingBox: Equatable, Sendable {
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

    public init?(region: MKCoordinateRegion) {
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta

        guard latDelta.isFinite, lonDelta.isFinite, latDelta > 0, lonDelta > 0 else {
            return nil
        }

        let center = region.center
        let halfLat = latDelta / 2.0
        let halfLon = lonDelta / 2.0

        let minLat = max(-90.0, center.latitude - halfLat)
        let maxLat = min(90.0, center.latitude + halfLat)
        let minLon = max(-180.0, center.longitude - halfLon)
        let maxLon = min(180.0, center.longitude + halfLon)

        self.init(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }

    public var queryValue: String {
        let format = "%.6f"
        return String(format: "\(format),\(format),\(format),\(format)", minLon, minLat, maxLon, maxLat)
    }
}
