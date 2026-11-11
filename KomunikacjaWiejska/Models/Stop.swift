import CoreLocation
import Foundation

// MARK: - Positional tuple decoding

/// Minimum positional element counts expected from API tuples.
enum StopTupleIndex { static let minimumCount = 10 }
enum RouteTupleIndex { static let minimumCount = 7 }
enum EntranceTupleIndex { static let minimumCount = 2 }

/// Sequentially reads positional tuple fields, maintaining the field index
/// and providing contextual error diagnostics on decoding failures.
struct TupleReader {
    var container: UnkeyedDecodingContainer
    let typeName: String
    private(set) var currentIndex: Int = 0

    init(container: UnkeyedDecodingContainer, typeName: String, minimumCount: Int) throws {
        self.container = container
        self.typeName = typeName
        // Count may be nil for streaming decoders; validate when available.
        if let count = container.count {
            guard count >= minimumCount else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "\(typeName): expected at least \(minimumCount) elements, got \(count)"
                ))
            }
        }
    }

    private mutating func readNext<T>(_ operation: (inout UnkeyedDecodingContainer) throws -> T, field: String) throws -> T {
        let index = currentIndex
        currentIndex += 1
        do {
            return try operation(&container)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(typeName): cannot decode field '\(field)' at index \(index) as \(T.self)",
                underlyingError: error
            ))
        }
    }

    mutating func decode<T: Decodable>(_ type: T.Type = T.self, field: String) throws -> T {
        try readNext({ try $0.decode(type) }, field: field)
    }

    mutating func decodeIfPresent<T: Decodable>(_ type: T.Type = T.self, field: String) throws -> T? {
        try readNext({ try $0.decodeIfPresent(type) }, field: field)
    }

    mutating func nestedReader(field: String, minimumCount: Int) throws -> TupleReader {
        let nested = try container.nestedUnkeyedContainer()
        return try TupleReader(container: nested, typeName: "\(typeName).\(field)", minimumCount: minimumCount)
    }
}

enum TupleDecoding {
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

struct StopRoute: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let city: String
    let name: String
    let longName: String
    let agency: String
    let type: RouteType
    let color: String

    init(
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

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(
            container: try decoder.unkeyedContainer(),
            typeName: "StopRoute",
            minimumCount: RouteTupleIndex.minimumCount
        )
        self.id = try reader.decode(field: "id")
        self.city = try reader.decode(field: "city")
        self.name = try reader.decode(field: "name")
        self.longName = try reader.decode(field: "longName")
        self.agency = try reader.decode(field: "agency")
        self.type = try reader.decode(field: "type")
        self.color = try reader.decode(field: "color")
    }
}

struct StopEntrance: Identifiable, Hashable, Sendable {
    /// Deterministic identity: the API has no entrance ID, so it is derived
    /// from the parent stop ID and the entrance's position in the tuple.
    /// Entrance ordering is therefore part of identity: identical responses
    /// produce identical IDs, and duplicate names/coordinates stay distinct.
    let id: String
    let name: String
    let longitude: Double
    let latitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Stop: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let city: String
    let name: String
    let code: String
    let longitude: Double
    let latitude: Double
    let vehicleTypes: [RouteType]
    let bearing: Int?
    let direction: String
    let routes: [StopRoute]
    let entrances: [StopEntrance]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryVehicleType: RouteType {
        vehicleTypes.first ?? .unknown
    }

    var displayName: String {
        code.isEmpty ? name : "\(name) (\(code))"
    }

    init(
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

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(
            container: try decoder.unkeyedContainer(),
            typeName: "Stop",
            minimumCount: StopTupleIndex.minimumCount
        )

        let id = try reader.decode(String.self, field: "id")
        self.id = id
        self.city = try reader.decode(field: "city")
        self.name = try reader.decode(field: "name")
        self.code = try reader.decode(field: "code")

        var locationReader = try reader.nestedReader(field: "location", minimumCount: 2)
        let longitude = try locationReader.decode(Double.self, field: "longitude")
        let latitude = try locationReader.decode(Double.self, field: "latitude")
        try TupleDecoding.validateCoordinates(
            longitude: longitude,
            latitude: latitude,
            in: "Stop"
        )
        self.longitude = longitude
        self.latitude = latitude

        self.vehicleTypes = try reader.decode(field: "vehicleTypes")

        // Bearing is optional; normalize it into 0..<360 when present.
        let rawBearing: Int? = try reader.decodeIfPresent(Int.self, field: "bearing")
        if let rawBearing {
            self.bearing = ((rawBearing % 360) + 360) % 360
        } else {
            self.bearing = nil
        }

        self.direction = try reader.decode(field: "direction")
        self.routes = try reader.decode(field: "routes")
        self.entrances = try Self.decodeEntrances(from: &reader.container, stopID: id)
    }

    /// Entrances are decoded here so each one receives a stable ID derived
    /// from the stop ID and tuple position.
    private static func decodeEntrances(
        from container: inout UnkeyedDecodingContainer,
        stopID: String
    ) throws -> [StopEntrance] {
        var listContainer = try container.nestedUnkeyedContainer()
        var entrances: [StopEntrance] = []
        var index = 0
        while !listContainer.isAtEnd {
            var reader = try TupleReader(
                container: try listContainer.nestedUnkeyedContainer(),
                typeName: "StopEntrance",
                minimumCount: EntranceTupleIndex.minimumCount
            )
            let name = try reader.decode(String.self, field: "name")
            var locationReader = try reader.nestedReader(field: "location", minimumCount: 2)
            let longitude = try locationReader.decode(Double.self, field: "longitude")
            let latitude = try locationReader.decode(Double.self, field: "latitude")
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

/// Explicitly nonisolated for cross-actor transfer from background decoding tasks in `ZbiorkomAPIClient`.
nonisolated struct StopsResponse: Decodable, Sendable {
    let stops: [Stop]

    init(stops: [Stop]) {
        self.stops = stops
    }
}
