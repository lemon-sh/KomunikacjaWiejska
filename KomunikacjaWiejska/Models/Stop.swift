import CoreLocation
import Foundation

// MARK: - Positional tuple decoding

/// Index layout of the API's positional `StopTuple`.
enum StopTupleIndex {
    static let id = 0
    static let city = 1
    static let name = 2
    static let code = 3
    static let location = 4
    static let vehicleTypes = 5
    static let bearing = 6
    static let direction = 7
    static let routes = 8
    static let entrances = 9
    static let minimumCount = 10
}

/// Index layout of the API's positional `RouteTuple`.
enum RouteTupleIndex {
    static let id = 0
    static let city = 1
    static let name = 2
    static let longName = 3
    static let agency = 4
    static let type = 5
    static let color = 6
    static let minimumCount = 7
}

/// Index layout of the API's positional `EntranceTuple`.
enum EntranceTupleIndex {
    static let name = 0
    static let location = 1
    static let minimumCount = 2
}

enum TupleDecoding {
    /// Decodes one positional element and rethrows failures with the tuple
    /// type, field name, and index so malformed payloads are diagnosable.
    static func decode<T: Decodable>(
        _ type: T.Type,
        from container: inout UnkeyedDecodingContainer,
        field: String,
        index: Int,
        in typeName: String
    ) throws -> T {
        do {
            return try container.decode(type)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(typeName): cannot decode field '\(field)' at index \(index) as \(T.self)",
                underlyingError: error
            ))
        }
    }

    /// Validates that a tuple has at least the number of elements the schema
    /// requires. Extra trailing elements are ignored for forward compatibility.
    static func requireMinimumCount(
        _ container: UnkeyedDecodingContainer,
        _ minimum: Int,
        in typeName: String
    ) throws {
        guard let count = container.count else { return }
        guard count >= minimum else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(typeName): expected at least \(minimum) elements, got \(count)"
            ))
        }
    }

    static func validateCoordinates(
        longitude: Double,
        latitude: Double,
        in typeName: String
    ) throws {
        guard (-180.0...180.0).contains(longitude), (-90.0...90.0).contains(latitude) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "\(typeName): invalid coordinate pair (longitude: \(longitude), latitude: \(latitude))"
            ))
        }
    }
}

// MARK: - Models

public struct StopRoute: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let city: String
    public let name: String
    public let longName: String
    public let agency: String
    public let type: RouteType
    public let color: String

    public init(
        id: String,
        city: String,
        name: String,
        longName: String,
        agency: String,
        type: RouteType,
        color: String
    ) {
        self.id = id
        self.city = city
        self.name = name
        self.longName = longName
        self.agency = agency
        self.type = type
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try TupleDecoding.requireMinimumCount(container, RouteTupleIndex.minimumCount, in: "StopRoute")
        self.id = try TupleDecoding.decode(
            String.self, from: &container, field: "id",
            index: RouteTupleIndex.id, in: "StopRoute"
        )
        self.city = try TupleDecoding.decode(
            String.self, from: &container, field: "city",
            index: RouteTupleIndex.city, in: "StopRoute"
        )
        self.name = try TupleDecoding.decode(
            String.self, from: &container, field: "name",
            index: RouteTupleIndex.name, in: "StopRoute"
        )
        self.longName = try TupleDecoding.decode(
            String.self, from: &container, field: "longName",
            index: RouteTupleIndex.longName, in: "StopRoute"
        )
        self.agency = try TupleDecoding.decode(
            String.self, from: &container, field: "agency",
            index: RouteTupleIndex.agency, in: "StopRoute"
        )
        self.type = try TupleDecoding.decode(
            RouteType.self, from: &container, field: "type",
            index: RouteTupleIndex.type, in: "StopRoute"
        )
        self.color = try TupleDecoding.decode(
            String.self, from: &container, field: "color",
            index: RouteTupleIndex.color, in: "StopRoute"
        )
    }
}

public struct StopEntrance: Identifiable, Hashable, Sendable {
    /// Deterministic identity: the API has no entrance ID, so it is derived
    /// from the parent stop ID and the entrance's position in the tuple.
    /// Entrance ordering is therefore part of identity: identical responses
    /// produce identical IDs, and duplicate names/coordinates stay distinct.
    public let id: String
    public let name: String
    public let longitude: Double
    public let latitude: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(id: String, name: String, longitude: Double, latitude: Double) {
        self.id = id
        self.name = name
        self.longitude = longitude
        self.latitude = latitude
    }
}

public struct Stop: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let city: String
    public let name: String
    public let code: String
    public let longitude: Double
    public let latitude: Double
    public let vehicleTypes: [RouteType]
    public let bearing: Int?
    public let direction: String
    public let routes: [StopRoute]
    public let entrances: [StopEntrance]

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var primaryVehicleType: RouteType {
        vehicleTypes.first ?? .bus
    }

    public var displayName: String {
        if code.isEmpty {
            return name
        }
        return "\(name) (\(code))"
    }

    public init(
        id: String,
        city: String,
        name: String,
        code: String,
        longitude: Double,
        latitude: Double,
        vehicleTypes: [RouteType],
        bearing: Int?,
        direction: String,
        routes: [StopRoute],
        entrances: [StopEntrance]
    ) {
        self.id = id
        self.city = city
        self.name = name
        self.code = code
        self.longitude = longitude
        self.latitude = latitude
        self.vehicleTypes = vehicleTypes
        self.bearing = bearing
        self.direction = direction
        self.routes = routes
        self.entrances = entrances
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        try TupleDecoding.requireMinimumCount(container, StopTupleIndex.minimumCount, in: "Stop")

        let id = try TupleDecoding.decode(
            String.self, from: &container, field: "id",
            index: StopTupleIndex.id, in: "Stop"
        )
        self.id = id
        self.city = try TupleDecoding.decode(
            String.self, from: &container, field: "city",
            index: StopTupleIndex.city, in: "Stop"
        )
        self.name = try TupleDecoding.decode(
            String.self, from: &container, field: "name",
            index: StopTupleIndex.name, in: "Stop"
        )
        self.code = try TupleDecoding.decode(
            String.self, from: &container, field: "code",
            index: StopTupleIndex.code, in: "Stop"
        )

        var locationContainer = try container.nestedUnkeyedContainer()
        try TupleDecoding.requireMinimumCount(locationContainer, 2, in: "Stop.location")
        let longitude = try TupleDecoding.decode(
            Double.self, from: &locationContainer, field: "longitude",
            index: 0, in: "Stop.location"
        )
        let latitude = try TupleDecoding.decode(
            Double.self, from: &locationContainer, field: "latitude",
            index: 1, in: "Stop.location"
        )
        try TupleDecoding.validateCoordinates(
            longitude: longitude,
            latitude: latitude,
            in: "Stop"
        )
        self.longitude = longitude
        self.latitude = latitude

        self.vehicleTypes = try TupleDecoding.decode(
            [RouteType].self, from: &container, field: "vehicleTypes",
            index: StopTupleIndex.vehicleTypes, in: "Stop"
        )

        // Bearing is optional; normalize it into 0..<360 when present.
        let rawBearing: Int? = try container.decodeIfPresent(Int.self)
        if let rawBearing = rawBearing {
            self.bearing = ((rawBearing % 360) + 360) % 360
        } else {
            self.bearing = nil
        }

        self.direction = try TupleDecoding.decode(
            String.self, from: &container, field: "direction",
            index: StopTupleIndex.direction, in: "Stop"
        )
        self.routes = try TupleDecoding.decode(
            [StopRoute].self, from: &container, field: "routes",
            index: StopTupleIndex.routes, in: "Stop"
        )
        self.entrances = try Self.decodeEntrances(from: &container, stopID: id)
    }

    /// Entrances are decoded here (instead of via a plain `[StopEntrance]`
    /// decode) so each one can receive a stable ID derived from the stop ID
    /// and tuple position.
    private static func decodeEntrances(
        from container: inout UnkeyedDecodingContainer,
        stopID: String
    ) throws -> [StopEntrance] {
        var listContainer = try container.nestedUnkeyedContainer()
        var entrances: [StopEntrance] = []
        var index = 0
        while !listContainer.isAtEnd {
            var tuple = try listContainer.nestedUnkeyedContainer()
            try TupleDecoding.requireMinimumCount(tuple, EntranceTupleIndex.minimumCount, in: "StopEntrance")
            let name = try TupleDecoding.decode(
                String.self, from: &tuple, field: "name",
                index: EntranceTupleIndex.name, in: "StopEntrance"
            )
            var locationContainer = try tuple.nestedUnkeyedContainer()
            try TupleDecoding.requireMinimumCount(locationContainer, 2, in: "StopEntrance.location")
            let longitude = try TupleDecoding.decode(
                Double.self, from: &locationContainer, field: "longitude",
                index: 0, in: "StopEntrance.location"
            )
            let latitude = try TupleDecoding.decode(
                Double.self, from: &locationContainer, field: "latitude",
                index: 1, in: "StopEntrance.location"
            )
            try TupleDecoding.validateCoordinates(
                longitude: longitude,
                latitude: latitude,
                in: "StopEntrance"
            )
            entrances.append(
                StopEntrance(
                    id: "\(stopID)-entrance-\(index)",
                    name: name,
                    longitude: longitude,
                    latitude: latitude
                )
            )
            index += 1
        }
        return entrances
    }
}

/// `nonisolated` is required, not cosmetic: this project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes the synthesized
/// `Decodable` conformance MainActor-isolated. `ZbiorkomAPIClient` is an
/// independent actor and decodes off MainActor, so using such a conformance
/// there is rejected (warning now, error in Swift 6 mode, diagnostic
/// `IsolatedConformances`). If P5-3 moves the decoding entry point to a
/// nonisolated context or the project stops defaulting to MainActor isolation,
/// this attribute can be removed.
public nonisolated struct StopsResponse: Decodable, Sendable {
    public let stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }
}
