import CoreGraphics

/// Shared layout metrics for the map chrome. Values follow Apple HIG control
/// sizes; keeping them here avoids unexplained magic numbers in the views.
enum DesignTokens {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 8
    static let controlSpacing: CGFloat = 10
    static let bottomPadding: CGFloat = 16

    /// Minimum interactive target for icon-only controls.
    static let controlSize: CGFloat = 44
    static let compactControlSize: CGFloat = 30

    static let markerSize: CGFloat = 24
    static let markerSelectedSize: CGFloat = 30
    static let markerCompactSize: CGFloat = 7
    /// Map annotations intentionally cap their Dynamic Type growth: markers
    /// above this size would cover the map and obscure neighbouring stops.
    static let markerMaximumSize: CGFloat = 34

    static let badgeCornerRadius: CGFloat = 12
    static let modePreviewSize: CGFloat = 82
}
