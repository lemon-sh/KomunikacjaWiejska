import Foundation
import SwiftUI

/// Map marker for a live transit vehicle.
/// Supports two-tier rendering:
/// - Compact mode (> 2,000 m): minimal 7pt circle without shadows or heavy modifiers.
/// - Full mode (<= 2,000 m or selected): route pill badge with direction arrow, route type icon, and route name.
struct VehicleMarkerView: View, Equatable {
    let vehicle: VehiclePosition
    let isSelected: Bool
    let isCompact: Bool
    let heading: Double

    static func == (lhs: VehicleMarkerView, rhs: VehicleMarkerView) -> Bool {
        lhs.vehicle.id == rhs.vehicle.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isCompact == rhs.isCompact
            && lhs.vehicle.bearing == rhs.vehicle.bearing
            && (lhs.vehicle.bearing == nil || abs(lhs.heading - rhs.heading) < 0.5)
            && lhs.vehicle.coordinate.latitude == rhs.vehicle.coordinate.latitude
            && lhs.vehicle.coordinate.longitude == rhs.vehicle.coordinate.longitude
            && lhs.vehicle.routeName == rhs.vehicle.routeName
            && lhs.vehicle.routeType == rhs.vehicle.routeType
    }

    init(
        vehicle: VehiclePosition,
        isSelected: Bool = false,
        isCompact: Bool = false,
        heading: Double = 0
    ) {
        self.vehicle = vehicle
        self.isSelected = isSelected
        self.isCompact = isCompact
        self.heading = heading
    }

    /// Rotates the bearing relative to map heading.
    static func effectiveRotation(bearing: Int, heading: Double) -> Double {
        Double(bearing) - heading
    }

    private var accessibilityDescription: String {
        String(
            format: String(localized: "accessibility.vehicle"),
            vehicle.routeName,
            vehicle.headsign ?? ""
        )
    }

    var body: some View {
        Group {
            if isCompact && !isSelected {
                Circle()
                    .fill(vehicle.displayColor)
                    .frame(width: DesignTokens.vehicleCompactSize, height: DesignTokens.vehicleCompactSize)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    )
                    .frame(width: DesignTokens.controlSize, height: DesignTokens.controlSize)
                    .contentShape(Rectangle())
            } else {
                HStack(spacing: 4) {
                    if let bearing = vehicle.bearing {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(Self.effectiveRotation(bearing: bearing, heading: heading)))
                    }

                    Image(systemName: vehicle.routeType.systemImageName)
                        .font(.system(size: 9, weight: .semibold))

                    Text(vehicle.routeName)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(vehicle.displayColor)
                .foregroundStyle(vehicle.contrastingTextColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 1.5)
                )
                .shadow(
                    color: isSelected ? .black.opacity(0.35) : .black.opacity(0.2),
                    radius: isSelected ? 4 : 2,
                    x: 0,
                    y: isSelected ? 2 : 1
                )
                .scaleEffect(isSelected ? 1.2 : 1.0)
                .frame(minWidth: DesignTokens.controlSize, minHeight: DesignTokens.controlSize)
                .contentShape(Rectangle())
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        .zIndex(isSelected ? 2 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
