import SwiftUI

/// SwiftUI and localized presentation for `RouteType`, kept out of the model
/// so the model layer stays UI- and locale-free (ADR-0004).
extension RouteType {
    var defaultHexColor: String {
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
        case .aerialLift, .funicular, .monorail:
            return "#546E7A"
        case .unknown:
            // Neutral, clearly distinct from every real route type.
            return "#757575"
        }
    }

    var defaultColor: Color {
        Color(hex: defaultHexColor, fallback: .blue)
    }

    var systemImageName: String {
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
            return "questionmark.circle.fill"
        }
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
