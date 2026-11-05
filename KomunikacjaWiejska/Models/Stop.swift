import CoreLocation
import Foundation

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
        self.id = try container.decode(String.self)
        self.city = try container.decode(String.self)
        self.name = try container.decode(String.self)
        self.longName = try container.decode(String.self)
        self.agency = try container.decode(String.self)
        self.type = try container.decode(RouteType.self)
        self.color = try container.decode(String.self)
    }
}

public struct StopEntrance: Identifiable, Hashable, Sendable, Decodable {
    public var id: String { "\(name)_\(longitude)_\(latitude)" }
    public let name: String
    public let longitude: Double
    public let latitude: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(name: String, longitude: Double, latitude: Double) {
        self.name = name
        self.longitude = longitude
        self.latitude = latitude
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.name = try container.decode(String.self)
        var locationContainer = try container.nestedUnkeyedContainer()
        self.longitude = try locationContainer.decode(Double.self)
        self.latitude = try locationContainer.decode(Double.self)
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
        self.id = try container.decode(String.self)
        self.city = try container.decode(String.self)
        self.name = try container.decode(String.self)
        self.code = try container.decode(String.self)

        var locContainer = try container.nestedUnkeyedContainer()
        self.longitude = try locContainer.decode(Double.self)
        self.latitude = try locContainer.decode(Double.self)

        self.vehicleTypes = try container.decode([RouteType].self)
        self.bearing = try container.decodeIfPresent(Int.self)
        self.direction = try container.decode(String.self)
        self.routes = try container.decode([StopRoute].self)
        self.entrances = try container.decode([StopEntrance].self)
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
