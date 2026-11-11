import CoreLocation
import Foundation

/// Positional `Stop`, `StopRoute`, and `StopEntrance` models supporting both
/// 7-tuple `mapFeatures` stops and full 10-tuple `stops/{id}/stream` stops.

/// 7-element route tuple embedded in stops, vehicles, trips, and departures:
/// `[id, city, name, longName, agency, type, color]`.
nonisolated struct StopRoute: Identifiable, Hashable, Sendable, Decodable {
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
        var reader = try TupleReader(decoder: decoder, context: "StopRoute", minimumCount: 6)
        self.id = try reader.decode(String.self, field: "id")
        self.city = try reader.decode(String.self, field: "city")
        self.name = try reader.decode(String.self, field: "name")
        self.longName = try reader.decodeNonEmptyString(field: "longName") ?? ""
        self.agency = try reader.decodeNonEmptyString(field: "agency") ?? "default"
        let rawType = try reader.decode(Int.self, field: "type")
        self.type = RouteType(rawValue: rawType) ?? .unknown
        self.color = try reader.decodeNonEmptyString(field: "color") ?? ""
    }
}

/// 2-element stop exit/entrance tuple: `[name, [longitude, latitude]]`.
nonisolated struct StopEntrance: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Decodes `[id, city, name, code, [lon, lat], types, bearing, direction?, routes?, exits?]`.
nonisolated struct Stop: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let city: String
    let name: String
    let code: String
    let latitude: Double
    let longitude: Double
    let vehicleTypes: [RouteType]
    let bearing: Double?
    let direction: String
    let routes: [StopRoute]
    let entrances: [StopEntrance]
    let hasFullMetadata: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryVehicleType: RouteType {
        vehicleTypes.first ?? .unknown
    }

    var isRailOrSubway: Bool {
        primaryVehicleType == .subway || primaryVehicleType == .rail
    }

    init(
        id: String,
        city: String,
        name: String,
        code: String,
        latitude: Double,
        longitude: Double,
        vehicleTypes: [RouteType],
        bearing: Double?,
        direction: String = "",
        routes: [StopRoute] = [],
        entrances: [StopEntrance] = [],
        hasFullMetadata: Bool? = nil
    ) {
        self.id = id
        self.city = city
        self.name = name
        self.code = code
        self.latitude = latitude
        self.longitude = longitude
        self.vehicleTypes = vehicleTypes
        self.bearing = Self.normalizeBearing(bearing)
        self.direction = direction
        self.routes = routes
        self.entrances = entrances
        self.hasFullMetadata = hasFullMetadata ?? (!direction.isEmpty || !routes.isEmpty || !entrances.isEmpty)
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "Stop", minimumCount: 7)
        let id = try reader.decode(String.self, field: "id")
        let city = try reader.decode(String.self, field: "city")
        let name = try reader.decode(String.self, field: "name")
        let code = try reader.decodeNonEmptyString(field: "code") ?? ""
        let location = try reader.decode(CoordinatePair.self, field: "location")
        let rawTypes = try reader.decode([Int].self, field: "types")
        let vehicleTypes = rawTypes.map { RouteType(rawValue: $0) ?? .unknown }
        let rawBearing = try reader.decodeOptional(Double.self)

        let hasRemainingMetadata = reader.hasMore
        let direction = try reader.decodeNonEmptyString(field: "direction") ?? ""
        let routes = try reader.decodeOptional([StopRoute].self) ?? []
        let rawExits = try reader.decodeOptional([RawEntranceTuple].self) ?? []
        let entrances = rawExits.enumerated().map { index, exit in
            StopEntrance(
                id: "\(id)-entrance-\(index)",
                name: exit.name,
                latitude: exit.location.latitude,
                longitude: exit.location.longitude
            )
        }

        self.init(
            id: id,
            city: city,
            name: name,
            code: code,
            latitude: location.latitude,
            longitude: location.longitude,
            vehicleTypes: vehicleTypes,
            bearing: rawBearing,
            direction: direction,
            routes: routes,
            entrances: entrances,
            hasFullMetadata: hasRemainingMetadata
        )
    }

    static func normalizeBearing(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        let wrapped = raw.truncatingRemainder(dividingBy: 360.0)
        return wrapped < 0 ? wrapped + 360.0 : wrapped
    }
}

private nonisolated struct RawEntranceTuple: Decodable {
    let name: String
    let location: CoordinatePair

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "StopEntrance", minimumCount: 2)
        self.name = try reader.decode(String.self, field: "name")
        self.location = try reader.decode(CoordinatePair.self, field: "location")
    }
}
