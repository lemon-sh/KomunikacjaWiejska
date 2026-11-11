import SwiftUI

/// Rounded route badge (`VehicleMarkerView`) and compact overview dot (`DotMarkerView`).

struct VehicleMarkerView: View, Equatable {
    let vehicle: VehiclePosition
    let heading: Double
    let isSelected: Bool

    static func == (lhs: VehicleMarkerView, rhs: VehicleMarkerView) -> Bool {
        lhs.vehicle.id == rhs.vehicle.id
            && lhs.vehicle.routeName == rhs.vehicle.routeName
            && lhs.vehicle.routeColor == rhs.vehicle.routeColor
            && lhs.vehicle.routeType == rhs.vehicle.routeType
            && lhs.vehicle.bearing == rhs.vehicle.bearing
            && (lhs.vehicle.bearing == nil || abs(lhs.heading - rhs.heading) < 0.5)
            && lhs.isSelected == rhs.isSelected
    }

    static func effectiveRotation(bearing: Double, heading: Double) -> Double {
        bearing - heading
    }

    private var accessibilityText: String {
        String(
            format: String(localized: "accessibility.vehicle"),
            vehicle.routeType.displayName,
            vehicle.routeName,
            vehicle.routeLongName
        )
    }

    var body: some View {
        HStack(spacing: 3) {
            if let bearing = vehicle.bearing {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(Self.effectiveRotation(bearing: bearing, heading: heading)))
            }

            Image(systemName: vehicle.routeType.systemImageName)
                .font(.system(size: 10, weight: .semibold))

            Text(vehicle.routeName)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(vehicle.displayColor)
        .foregroundStyle(vehicle.contrastingTextColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .frame(minWidth: DesignTokens.controlSize, minHeight: DesignTokens.controlSize)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 1.0), value: vehicle.bearing)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

/// Compact dot annotation matching `DotMarkers.tsx` (`circle-radius: 4`, `1pt` white border) when zoomed out.
struct DotMarkerView: View, Equatable {
    let dot: DotVehicle

    static func == (lhs: DotMarkerView, rhs: DotMarkerView) -> Bool {
        lhs.dot.colorHex == rhs.dot.colorHex
    }

    var body: some View {
        Circle()
            .fill(dot.displayColor)
            .overlay(
                Circle()
                    .strokeBorder(.white, lineWidth: 1)
            )
            .frame(width: MapConstants.dotMarkerSize, height: MapConstants.dotMarkerSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("map.dot.accessibility"))
    }
}
