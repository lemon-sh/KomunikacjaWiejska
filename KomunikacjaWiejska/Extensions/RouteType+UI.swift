import SwiftUI

/// SwiftUI presentation for `RouteType`, kept out of the model so the model
/// layer stays UI-free.
public extension RouteType {
    var defaultColor: Color {
        Color(hex: defaultHexColor, fallback: .blue)
    }
}
