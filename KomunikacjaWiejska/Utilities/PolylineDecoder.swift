import CoreLocation
import Foundation

/// Google Encoded Polyline decoder (precision `1e6`).

nonisolated enum PolylineDecoder {
    /// Decodes a Google-encoded polyline string using `1e6` coordinate precision.
    static func decode(_ encoded: String, precision: Double = 1_000_000.0) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }

        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(max(bytes.count / 4, 8))

        var index = 0
        var latitude: Int64 = 0
        var longitude: Int64 = 0

        while index < bytes.count {
            guard let deltaLat = decodeComponent(bytes: bytes, index: &index),
                  let deltaLon = decodeComponent(bytes: bytes, index: &index) else {
                break
            }

            latitude += deltaLat
            longitude += deltaLon

            let coord = CLLocationCoordinate2D(
                latitude: Double(latitude) / precision,
                longitude: Double(longitude) / precision
            )
            if coord.latitude.isFinite,
               coord.longitude.isFinite,
               (-90.0...90.0).contains(coord.latitude),
               (-180.0...180.0).contains(coord.longitude) {
                coordinates.append(coord)
            }
        }

        return coordinates
    }

    private static func decodeComponent(bytes: [UInt8], index: inout Int) -> Int64? {
        var result: Int64 = 0
        var shift: Int64 = 0

        while index < bytes.count {
            let byte = Int64(bytes[index]) - 63
            index += 1
            guard byte >= 0 else { return nil }

            result |= (byte & 0x1F) << shift
            shift += 5

            if byte < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
            if shift > 60 {
                return nil
            }
        }

        return nil
    }
}
