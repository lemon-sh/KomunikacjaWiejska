import CoreGraphics

/// Shared layout metrics for the map chrome. Values follow Apple HIG control
/// sizes; keeping them here avoids unexplained magic numbers in the views.
public enum DesignTokens {
    public static let horizontalPadding: CGFloat = 16
    public static let topPadding: CGFloat = 8
    public static let controlSpacing: CGFloat = 10
    public static let bottomPadding: CGFloat = 16

    /// Minimum interactive target for icon-only controls.
    public static let controlSize: CGFloat = 44
    public static let compactControlSize: CGFloat = 30

    public static let markerSize: CGFloat = 24
    public static let markerSelectedSize: CGFloat = 30
    public static let markerCompactSize: CGFloat = 7
    /// Map annotations intentionally cap their Dynamic Type growth: markers
    /// above this size would cover the map and obscure neighbouring stops.
    public static let markerMaximumSize: CGFloat = 34

    /// Height for the collapsed bottom sheet showing stop details.
    public static let sheetSmallDetentHeight: CGFloat = 240

    public static let badgeCornerRadius: CGFloat = 12
}
