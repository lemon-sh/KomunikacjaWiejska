import SwiftUI

public struct StopMarkerView: View {
    public let stop: Stop
    public let isSelected: Bool
    public let isCompact: Bool

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

    public var body: some View {
        if isCompact && !isSelected {
            Circle()
                .fill(markerColor)
                .frame(width: 7, height: 7)
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
                            .frame(width: 8, height: 8)
                            .foregroundStyle(markerColor)
                            .offset(y: -14)
                    }
                    .rotationEffect(.degrees(Double(bearing)))
                }

                // Main circular badge
                Circle()
                    .fill(markerColor)
                    .frame(width: isSelected ? 30 : 24, height: isSelected ? 30 : 24)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1.5)

                // Icon inside badge
                Image(systemName: stop.primaryVehicleType.systemImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isSelected ? 15 : 12, height: isSelected ? 15 : 12)
                    .foregroundStyle(.white)
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.snappy(duration: 0.2), value: isSelected)
        }
    }
}
