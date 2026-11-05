import SwiftUI

/// SwiftUI and localized presentation for `RouteType`, kept out of the model
/// so the model layer stays UI- and locale-free.
public extension RouteType {
    var defaultColor: Color {
        Color(hex: defaultHexColor, fallback: .blue)
    }

    var displayName: String {
        switch self {
        case .tram:
            return String(localized: "routeType.tram")
        case .subway:
            return String(localized: "routeType.subway")
        case .rail:
            return String(localized: "routeType.rail")
        case .bus:
            return String(localized: "routeType.bus")
        case .ferry:
            return String(localized: "routeType.ferry")
        case .aerialLift:
            return String(localized: "routeType.aerialLift")
        case .funicular:
            return String(localized: "routeType.funicular")
        case .trolleybus:
            return String(localized: "routeType.trolleybus")
        case .monorail:
            return String(localized: "routeType.monorail")
        case .unknown:
            return String(localized: "routeType.unknown")
        }
    }
}
