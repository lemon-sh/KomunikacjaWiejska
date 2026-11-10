import CoreLocation
import Foundation

/// Top-level response from `GET /api6-open/{city}/positions/{bbox}`.
nonisolated struct VehiclesResponse: Decodable, Sendable {
    let positions: [VehiclePosition]

    init(positions: [VehiclePosition]) {
        self.positions = positions
    }
}

/// Information identifying the physical vehicle and operator.
nonisolated struct VehicleInfo: Decodable, Sendable, Equatable {
    let id: String
    let type: String
    let agency: String
    let model: String?

    init(id: String, type: String, agency: String = "default", model: String? = nil) {
        self.id = id
        self.type = type
        self.agency = agency
        self.model = model
    }
}

/// A scheduled upcoming stop along a vehicle's active trip.
nonisolated struct VehicleUpcomingStop: Decodable, Sendable, Equatable, Identifiable {
    let sequence: Int
    let name: String
    let scheduledArrival: Int64
    let scheduledDeparture: Int64

    var id: Int { sequence }

    init(sequence: Int, name: String, scheduledArrival: Int64, scheduledDeparture: Int64) {
        self.sequence = sequence
        self.name = name
        self.scheduledArrival = scheduledArrival
        self.scheduledDeparture = scheduledDeparture
    }
}

/// Real-time live vehicle position as returned by the zbiorkom.live API.
nonisolated struct VehiclePosition: Decodable, Sendable, Identifiable, Equatable {
    let vehicle: VehicleInfo
    let routeName: String
    let routeColor: String
    let brigade: String
    let location: [Double]
    let timestamp: Int64
    let bearing: Int?
    let delay: Int
    let headsign: String?
    let upcomingStops: [VehicleUpcomingStop]
    let url: String

    /// Deterministic identifier composed of operator agency, vehicle route type, and fleet number.
    var id: String {
        "\(vehicle.agency):\(vehicle.type):\(vehicle.id)"
    }

    var coordinate: CLLocationCoordinate2D {
        guard location.count >= 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(latitude: location[1], longitude: location[0])
    }

    var latitude: Double {
        location.count >= 2 ? location[1] : 0
    }

    var longitude: Double {
        location.count >= 2 ? location[0] : 0
    }

    var delaySeconds: Int {
        delay / 1_000
    }

    var delayMinutes: Int {
        delay / 60_000
    }

    var routeType: RouteType {
        if let intType = Int(vehicle.type) {
            return RouteType(rawValue: intType) ?? .unknown
        }
        return .unknown
    }

    init(
        vehicle: VehicleInfo,
        routeName: String,
        routeColor: String,
        brigade: String = "",
        location: [Double],
        timestamp: Int64 = 0,
        bearing: Int? = nil,
        delay: Int = 0,
        headsign: String? = nil,
        upcomingStops: [VehicleUpcomingStop] = [],
        url: String = ""
    ) {
        self.vehicle = vehicle
        self.routeName = routeName
        self.routeColor = routeColor
        self.brigade = brigade
        self.location = location
        self.timestamp = timestamp
        self.bearing = bearing
        self.delay = delay
        self.headsign = headsign
        self.upcomingStops = upcomingStops
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case vehicle
        case routeName
        case routeColor
        case brigade
        case location
        case timestamp
        case bearing
        case delay
        case headsign
        case upcomingStops
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vehicle = try container.decode(VehicleInfo.self, forKey: .vehicle)
        self.routeName = try container.decode(String.self, forKey: .routeName)
        self.routeColor = try container.decode(String.self, forKey: .routeColor)
        self.brigade = (try? container.decode(String.self, forKey: .brigade)) ?? ""
        self.location = try container.decode([Double].self, forKey: .location)
        self.timestamp = try container.decode(Int64.self, forKey: .timestamp)
        self.bearing = try container.decodeIfPresent(Int.self, forKey: .bearing)
        self.delay = (try? container.decode(Int.self, forKey: .delay)) ?? 0
        self.headsign = try container.decodeIfPresent(String.self, forKey: .headsign)
        self.upcomingStops = (try? container.decodeIfPresent([VehicleUpcomingStop].self, forKey: .upcomingStops)) ?? []
        self.url = (try? container.decode(String.self, forKey: .url)) ?? ""
    }

    static func == (lhs: VehiclePosition, rhs: VehiclePosition) -> Bool {
        lhs.id == rhs.id
            && lhs.routeName == rhs.routeName
            && lhs.routeColor == rhs.routeColor
            && lhs.timestamp == rhs.timestamp
            && lhs.bearing == rhs.bearing
            && lhs.delay == rhs.delay
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
    }
}
