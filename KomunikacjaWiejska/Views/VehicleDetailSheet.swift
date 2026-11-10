import Foundation
import SwiftUI

/// Non-blocking bottom sheet displaying selected vehicle details and placeholder for upcoming stops.
struct VehicleDetailSheet: View {
    let vehicle: VehiclePosition
    let onDismiss: () -> Void

    init(vehicle: VehiclePosition, onDismiss: @escaping () -> Void) {
        self.vehicle = vehicle
        self.onDismiss = onDismiss
    }

    private var delayColor: Color {
        if vehicle.delay > 60_000 {
            return .orange
        } else if vehicle.delay < -60_000 {
            return .blue
        } else {
            return .green
        }
    }

    private var delayText: String {
        let minutes = vehicle.delayMinutes
        if abs(vehicle.delay) <= 30_000 {
            return String(localized: "vehicle.delay.onTime")
        } else if minutes > 0 {
            return String(format: String(localized: "vehicle.delay.minutesLate"), minutes)
        } else {
            return String(format: String(localized: "vehicle.delay.minutesEarly"), abs(minutes))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerView

                    delayStatusCard

                    placeholderSection
                }
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .accessibilityLabel(Text("stop.sheet.close"))
                }
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: vehicle.routeType.systemImageName)
                    .font(.caption2.weight(.bold))
                    .frame(width: 14, height: 14)
                Text(vehicle.routeName)
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(vehicle.displayColor)
            .foregroundStyle(vehicle.contrastingTextColor)
            .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                if let headsign = vehicle.headsign, !headsign.isEmpty {
                    Text(headsign)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(vehicle.routeName)
                        .font(.headline)
                }

                if !vehicle.brigade.isEmpty {
                    Text(String(format: String(localized: "vehicle.brigade"), vehicle.brigade))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var delayStatusCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(delayColor)
                .frame(width: 8, height: 8)

            Text(delayText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(delayColor)

            Spacer()

            if let model = vehicle.vehicle.model, !model.isEmpty {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var placeholderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("vehicle.sheet.placeholder")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
