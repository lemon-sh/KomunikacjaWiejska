import SwiftUI

/// UI presentation helpers for `VehiclePosition`, kept isolated to `@MainActor`.
@MainActor
extension VehiclePosition {
    var displayColor: Color {
        Color(hex: routeColor, fallback: routeType.defaultColor)
    }

    var contrastingTextColor: Color {
        Color.contrastingTextColor(forHex: routeColor, fallback: .white)
    }
}
