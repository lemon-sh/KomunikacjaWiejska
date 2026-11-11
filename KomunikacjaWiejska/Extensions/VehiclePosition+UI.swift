import SwiftUI

/// Shared UI color helpers across `StopRoute`, `VehiclePosition`, and `DotVehicle`.

nonisolated extension StopRoute {
    var displayColor: Color {
        Color(hex: color, fallback: type.defaultColor)
    }

    var contrastingTextColor: Color {
        Color.contrastingTextColor(
            forHex: color.isEmpty ? type.defaultHexColor : color,
            fallback: .white
        )
    }
}

nonisolated extension VehiclePosition {
    var displayColor: Color {
        route.displayColor
    }

    var contrastingTextColor: Color {
        route.contrastingTextColor
    }
}

nonisolated extension DotVehicle {
    var displayColor: Color {
        Color(hex: colorHex, fallback: .accentColor)
    }
}
