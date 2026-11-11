import CoreLocation
import Foundation

/// Shared single-pass positional tuple decoding helpers.

nonisolated enum TupleDecodingError: Error, LocalizedError, Equatable, Sendable {
    case tupleTooShort(context: String, expectedMinimum: Int, actual: Int)
    case invalidCoordinate(context: String, longitude: Double, latitude: Double)
    case invalidValue(context: String, index: Int)

    var errorDescription: String? {
        switch self {
        case let .tupleTooShort(context, expectedMinimum, actual):
            return "Tuple '\(context)' too short: expected at least \(expectedMinimum) elements, got \(actual)."
        case let .invalidCoordinate(context, longitude, latitude):
            return "Invalid coordinate in '\(context)': lon=\(longitude), lat=\(latitude)."
        case let .invalidValue(context, index):
            return "Invalid value in '\(context)' at index \(index)."
        }
    }
}

/// Decodes a GeoJSON-ordered `[longitude, latitude]` pair into a validated coordinate.
nonisolated struct CoordinatePair: Decodable, Equatable, Sendable {
    let longitude: Double
    let latitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(longitude: Double, latitude: Double) throws {
        guard longitude.isFinite,
              latitude.isFinite,
              (-180.0...180.0).contains(longitude),
              (-90.0...90.0).contains(latitude) else {
            throw TupleDecodingError.invalidCoordinate(
                context: "CoordinatePair",
                longitude: longitude,
                latitude: latitude
            )
        }
        self.longitude = longitude
        self.latitude = latitude
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let count = container.count ?? 0
        guard !container.isAtEnd else {
            throw TupleDecodingError.tupleTooShort(context: "CoordinatePair", expectedMinimum: 2, actual: count)
        }
        let lon = try container.decode(Double.self)
        guard !container.isAtEnd else {
            throw TupleDecodingError.tupleTooShort(context: "CoordinatePair", expectedMinimum: 2, actual: 1)
        }
        let lat = try container.decode(Double.self)
        try self.init(longitude: lon, latitude: lat)
    }
}

/// Decodes `[minLongitude, minLatitude, maxLongitude, maxLatitude]` bounding box arrays.
extension BoundingBox {
    nonisolated init(tupleDecoder decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let actualCount = container.count ?? 0
        guard actualCount >= 4 else {
            throw TupleDecodingError.tupleTooShort(context: "BoundingBox", expectedMinimum: 4, actual: actualCount)
        }
        let minLon = try container.decode(Double.self)
        let minLat = try container.decode(Double.self)
        let maxLon = try container.decode(Double.self)
        let maxLat = try container.decode(Double.self)
        self.init(
            minLon: minLon,
            minLat: minLat,
            maxLon: maxLon,
            maxLat: maxLat
        )
    }

    /// Computes Web Mercator zoom rounded to 0.5 increments for `/api6` `mapFeatures` queries.
    nonisolated func webMercatorZoom(viewportWidth: Double = 393.0) -> Double {
        let span = max(maxLon - minLon, 1e-6)
        let rawZoom = log2((360.0 / span) * (max(viewportWidth, 1.0) / 256.0))
        let clamped = min(max(rawZoom, 0.0), 20.0)
        return (clamped * 2.0).rounded() / 2.0
    }
}

/// Single-pass sequential reader for positional JSON tuple arrays (`api6`).
nonisolated struct TupleReader {
    private var container: UnkeyedDecodingContainer
    private let context: String

    init(decoder: Decoder, context: String, minimumCount: Int) throws {
        let container = try decoder.unkeyedContainer()
        if let count = container.count, count < minimumCount {
            throw TupleDecodingError.tupleTooShort(
                context: context,
                expectedMinimum: minimumCount,
                actual: count
            )
        }
        self.container = container
        self.context = context
    }

    var currentIndex: Int { container.currentIndex }
    var hasMore: Bool { !container.isAtEnd }

    mutating func decode<T: Decodable>(_ type: T.Type, field: String) throws -> T {
        let index = container.currentIndex
        guard !container.isAtEnd else {
            throw TupleDecodingError.tupleTooShort(
                context: "\(context).\(field)",
                expectedMinimum: index + 1,
                actual: index
            )
        }
        return try container.decode(type)
    }

    mutating func decodeOptional<T: Decodable>(_ type: T.Type) throws -> T? {
        guard !container.isAtEnd else {
            return nil
        }
        if try container.decodeNil() {
            return nil
        }
        return try container.decode(type)
    }

    mutating func decodeNonEmptyString(field: String) throws -> String? {
        let value = try decodeOptional(String.self)
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    mutating func decodeCoordinate(field: String) throws -> CLLocationCoordinate2D {
        let pair = try decode(CoordinatePair.self, field: field)
        return pair.coordinate
    }
}
