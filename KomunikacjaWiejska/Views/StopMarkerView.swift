import SwiftUI

/// Map annotation badge for transit stops (circle for surface stops, rounded square for rail/metro).

struct StopMarkerView: View, Equatable {
    let stop: Stop
    let heading: Double
    let isSelected: Bool

    static func == (lhs: StopMarkerView, rhs: StopMarkerView) -> Bool {
        lhs.stop.id == rhs.stop.id
            && lhs.stop.name == rhs.stop.name
            && lhs.stop.code == rhs.stop.code
            && lhs.stop.vehicleTypes == rhs.stop.vehicleTypes
            && lhs.stop.bearing == rhs.stop.bearing
            && (lhs.stop.bearing == nil || abs(lhs.heading - rhs.heading) < 0.5)
            && lhs.isSelected == rhs.isSelected
    }

    @ScaledMetric(relativeTo: .body) private var scaledMarkerSize: CGFloat = DesignTokens.markerSize

    private var iconColor: Color {
        stop.primaryVehicleType.defaultColor
    }

    private var circleSize: CGFloat {
        min(max(scaledMarkerSize, DesignTokens.markerSize), DesignTokens.markerMaximumSize)
    }

    private var selectedScaleFactor: CGFloat {
        DesignTokens.markerSelectedSize / DesignTokens.markerSize
    }

    static func effectiveRotation(bearing: Double, heading: Double) -> Double {
        bearing - heading
    }

    private var directionalFrameSize: CGFloat {
        circleSize + 10
    }

    private var accessibilityText: String {
        let namePart = stop.code.isEmpty ? stop.name : "\(stop.name) \(stop.code)"
        return String(
            format: String(localized: "accessibility.stop"),
            namePart,
            stop.primaryVehicleType.displayName
        )
    }

    var body: some View {
        ZStack {
            if let bearing = stop.bearing, !stop.isRailOrSubway {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 0)
                    .offset(y: -(circleSize / 2 + 4))
                    .rotationEffect(.degrees(Self.effectiveRotation(bearing: bearing, heading: heading)))
            }

            badgeContent
                .frame(width: circleSize, height: circleSize)
                .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1.5)
        }
        .frame(width: directionalFrameSize, height: directionalFrameSize)
        .scaleEffect(isSelected ? selectedScaleFactor : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
        .frame(minWidth: DesignTokens.controlSize, minHeight: DesignTokens.controlSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var badgeContent: some View {
        let cornerRadius = stop.isRailOrSubway ? CGFloat(6) : circleSize / 2
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        shape
            .fill(iconColor)
            .overlay(
                shape.stroke(.white, lineWidth: isSelected ? 3 : 2)
            )
            .overlay(
                Image(systemName: stop.primaryVehicleType.systemImageName)
                    .font(.system(size: circleSize * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}
