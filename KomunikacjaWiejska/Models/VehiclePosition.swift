import CoreLocation
import Foundation

/// Positional `VehiclePosition` (6-tuple and 9-tuple) and `DotVehicle` models.

/// Zoomed-out vehicle dot returned in `mapFeatures/{zoom}/{bbox}/stream` `dots` array:
/// `[routeColor, [longitude, latitude]]`.
nonisolated struct DotVehicle: Identifiable, Hashable, Sendable {
    let id: String
    let colorHex: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String, colorHex: String, latitude: Double, longitude: Double) {
        self.id = id
        self.colorHex = colorHex
        self.latitude = latitude
        self.longitude = longitude
    }
}

nonisolated struct RawDotTuple: Decodable, Sendable {
    let colorHex: String
    let latitude: Double
    let longitude: Double

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "DotVehicle", minimumCount: 2)
        self.colorHex = try reader.decode(String.self, field: "routeColor")
        let coord = try reader.decode(CoordinatePair.self, field: "location")
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }
}

/// Live vehicle position decoded from `/api6` 6-element (`mapFeatures`, `stops/.../stream`)
/// or 9-element (`positions/.../stream`, `trips/.../stream`) tuples:
/// `[id, city, route, brigade, [lon, lat], bearing, lastPing?, tripId?, percentTraveled?]`.
nonisolated struct VehiclePosition: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let city: String
    let route: StopRoute
    let brigade: String?
    let latitude: Double
    let longitude: Double
    let bearing: Double?
    let lastPingMs: Int64?
    let tripId: String?
    let percentTraveled: Double?

    var routeId: String { route.id }
    var routeName: String { route.name }
    var routeLongName: String { route.longName }
    var routeAgency: String { route.agency }
    var routeType: RouteType { route.type }
    var routeColor: String { route.color }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var lastPingDate: Date? {
        guard let lastPingMs, lastPingMs > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(lastPingMs) / 1_000.0)
    }

    init(
        id: String,
        city: String,
        route: StopRoute,
        brigade: String? = nil,
        latitude: Double,
        longitude: Double,
        bearing: Double? = nil,
        lastPingMs: Int64? = nil,
        tripId: String? = nil,
        percentTraveled: Double? = nil
    ) {
        self.id = id
        self.city = city
        self.route = route
        self.brigade = brigade?.isEmpty == true ? nil : brigade
        self.latitude = latitude
        self.longitude = longitude
        self.bearing = Stop.normalizeBearing(bearing)
        self.lastPingMs = lastPingMs
        self.tripId = tripId?.isEmpty == true ? nil : tripId
        self.percentTraveled = percentTraveled
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "VehiclePosition", minimumCount: 6)
        let id = try reader.decode(String.self, field: "id")
        let city = try reader.decode(String.self, field: "city")
        let route = try reader.decode(StopRoute.self, field: "route")
        let brigade = try reader.decodeNonEmptyString(field: "brigade")
        let coord = try reader.decode(CoordinatePair.self, field: "location")
        let bearing = try reader.decodeOptional(Double.self)
        let lastPingMs = try reader.decodeOptional(Int64.self)
        let tripId = try reader.decodeNonEmptyString(field: "trip")
        let percentTraveled = try reader.decodeOptional(Double.self)

        self.init(
            id: id,
            city: city,
            route: route,
            brigade: brigade,
            latitude: coord.latitude,
            longitude: coord.longitude,
            bearing: bearing,
            lastPingMs: lastPingMs,
            tripId: tripId,
            percentTraveled: percentTraveled
        )
    }
}
