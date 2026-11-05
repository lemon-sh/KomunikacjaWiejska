import CoreLocation
import Foundation

public enum RouteType: Int, Codable, CaseIterable, Sendable {
    case tram = 0
    case subway = 1
    case rail = 2
    case bus = 3
    case ferry = 4
    case aerialLift = 6
    case funicular = 7
    case trolleybus = 11
    case monorail = 12
    case unknown = -1

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = RouteType(rawValue: rawValue) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .tram:
            return "Tramwaj"
        case .subway:
            return "Metro"
        case .rail:
            return "Kolej"
        case .bus:
            return "Autobus"
        case .ferry:
            return "Prom"
        case .aerialLift:
            return "Kolej linowa"
        case .funicular:
            return "Kolejka linowo-terenowa"
        case .trolleybus:
            return "Trolejbus"
        case .monorail:
            return "Monorail"
        case .unknown:
            return "Inny"
        }
    }

    public var systemImageName: String {
        switch self {
        case .tram:
            return "tram.fill"
        case .subway:
            return "tram.fill.tunnel"
        case .rail:
            return "train.side.front.car"
        case .bus:
            return "bus.fill"
        case .ferry:
            return "ferry.fill"
        case .aerialLift:
            return "cablecar.fill"
        case .funicular:
            return "cablecar"
        case .trolleybus:
            return "bus.doubledecker.fill"
        case .monorail:
            return "train.side.middle.car"
        case .unknown:
            return "mappin.circle.fill"
        }
    }

    public var defaultHexColor: String {
        switch self {
        case .tram:
            return "#E53935"
        case .subway:
            return "#1E88E5"
        case .rail:
            return "#43A047"
        case .bus:
            return "#FB8C00"
        case .ferry:
            return "#00ACC1"
        case .trolleybus:
            return "#8E24AA"
        case .aerialLift, .funicular, .monorail, .unknown:
            return "#546E7A"
        }
    }
}
