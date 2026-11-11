import Foundation

nonisolated enum RouteType: Int, Codable, CaseIterable, Sendable {
    case tram = 0
    case subway = 1
    case rail = 2
    case bus = 3
    case ferry = 4
    case aerialLift = 6
    case funicular = 7
    case trolleybus = 11
    case monorail = 12
    /// Sentinel for raw values the API adds later. Not a real GTFS type, so it
    /// is excluded from `displayableCases` and never offered as a filter.
    case unknown = -1

    /// Cases that represent actual transit modes (everything except `.unknown`).
    static var displayableCases: [RouteType] {
        allCases.filter { $0 != .unknown }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = RouteType(rawValue: rawValue) ?? .unknown
    }
}
