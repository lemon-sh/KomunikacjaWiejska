import Foundation
import SwiftUI

public struct StopMarkerView: View {
    public let stop: Stop
    private let viewModel: MapViewModel?
    private let explicitIsSelected: Bool?
    private let explicitIsCompact: Bool?

    /// `@ScaledMetric` keeps markers legible at larger text sizes, capped so
    /// they never cover the map or neighbouring stops.
    @ScaledMetric(relativeTo: .body) private var scaledMarkerSize: CGFloat = DesignTokens.markerSize

    public init(
        stop: Stop,
        viewModel: MapViewModel
    ) {
        self.stop = stop
        self.viewModel = viewModel
        self.explicitIsSelected = nil
        self.explicitIsCompact = nil
    }

    public init(
        stop: Stop,
        isSelected: Bool = false,
        isCompact: Bool = false
    ) {
        self.stop = stop
        self.viewModel = nil
        self.explicitIsSelected = isSelected
        self.explicitIsCompact = isCompact
    }

    private var isSelected: Bool {
        explicitIsSelected ?? (viewModel?.selectedStopID == stop.id)
    }

    private var isCompact: Bool {
        explicitIsCompact ?? (viewModel?.isCompactDisplayMode ?? false)
    }

    private var markerColor: Color {
        Color(hex: stop.primaryVehicleType.defaultHexColor, fallback: .blue)
    }

    private var badgeSize: CGFloat {
        min(max(scaledMarkerSize, DesignTokens.markerSize), DesignTokens.markerMaximumSize)
    }

    private var compactSize: CGFloat {
        min(badgeSize * 0.3, 9)
    }

    private var iconSize: CGFloat {
        badgeSize * 0.5
    }

    private var notchSize: CGFloat {
        badgeSize / 3
    }

    private var notchOffset: CGFloat {
        -(badgeSize / 2 + 2)
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
                    .frame(width: DesignTokens.compactControlSize, height: DesignTokens.compactControlSize)
                    .contentShape(Rectangle())
                    .transition(.scale.combined(with: .opacity))
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
                        .frame(width: badgeSize, height: badgeSize)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 2)
                        )
                        .shadow(
                            color: isSelected ? .black.opacity(0.35) : .black.opacity(0.25),
                            radius: isSelected ? 4 : 3,
                            x: 0,
                            y: isSelected ? 2 : 1.5
                        )

                    // Icon inside badge
                    Image(systemName: stop.primaryVehicleType.systemImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(.white)
                }
                .frame(
                    width: badgeSize + notchSize * 2,
                    height: badgeSize + notchSize * 2
                )
                .scaleEffect(isSelected ? 1.25 : 1.0)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        .zIndex(isSelected ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
