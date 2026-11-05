import Foundation
import SwiftUI

public struct StopMarkerView: View {
    public let stop: Stop
    public let isSelected: Bool
    public let isCompact: Bool

    /// `@ScaledMetric` keeps markers legible at larger text sizes, capped so
    /// they never cover the map or neighbouring stops.
    @ScaledMetric(relativeTo: .body) private var scaledMarkerSize: CGFloat = DesignTokens.markerSize

    public init(
        stop: Stop,
        isSelected: Bool = false,
        isCompact: Bool = false
    ) {
        self.stop = stop
        self.isSelected = isSelected
        self.isCompact = isCompact
    }

    private var markerColor: Color {
        Color(hex: stop.primaryVehicleType.defaultHexColor, fallback: .blue)
    }

    private var badgeSize: CGFloat {
        min(max(scaledMarkerSize, DesignTokens.markerSize), DesignTokens.markerMaximumSize)
    }

    private var effectiveBadgeSize: CGFloat {
        isSelected ? badgeSize + 6 : badgeSize
    }

    private var compactSize: CGFloat {
        min(badgeSize * 0.3, 9)
    }

    private var iconSize: CGFloat {
        effectiveBadgeSize * 0.5
    }

    private var notchSize: CGFloat {
        effectiveBadgeSize / 3
    }

    private var notchOffset: CGFloat {
        -(effectiveBadgeSize / 2 + 2)
    }

    private var accessibilityDescription: String {
        String(
            format: String(localized: "accessibility.stop"),
            stop.displayName,
            stop.primaryVehicleType.displayName
        )
    }

    public var body: some View {
        Group {
            if isCompact && !isSelected {
                Circle()
                    .fill(markerColor)
                    .frame(width: compactSize, height: compactSize)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
            } else {
                ZStack {
                    // Directional pointer / triangle notch if bearing is known.
                    // The triangle is offset inside a ZStack whose centre is the
                    // badge centre, then the whole container rotates, so the notch
                    // orbits the badge instead of spinning in place.
                    if let bearing = stop.bearing {
                        ZStack {
                            Image(systemName: "triangle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: notchSize, height: notchSize)
                                .foregroundStyle(markerColor)
                                .offset(y: notchOffset)
                        }
                        .rotationEffect(.degrees(Double(bearing)))
                    }

                    // Main circular badge
                    Circle()
                        .fill(markerColor)
                        .frame(width: effectiveBadgeSize, height: effectiveBadgeSize)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1.5)

                    // Icon inside badge
                    Image(systemName: stop.primaryVehicleType.systemImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(.white)
                }
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .animation(.snappy(duration: 0.2), value: isSelected)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
