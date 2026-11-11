import Foundation
import SwiftUI

/// Non-blocking bottom sheet displaying the selected vehicle's header and live upcoming-stop timeline.
struct VehicleDetailSheet: View {
    let vehicle: VehiclePosition
    let onDismiss: () -> Void

    enum DelayStatus: Equatable {
        case onTime
        case delayed(minutes: Int)
        case early(minutes: Int)

        var color: Color {
            switch self {
            case .onTime: .green
            case .delayed: .red
            case .early: .orange
            }
        }

        var isSignificantOffset: Bool {
            switch self {
            case .onTime: false
            case .delayed, .early: true
            }
        }

        var localizedText: String {
            switch self {
            case .onTime:
                return String(localized: "vehicle.delay.onTime")
            case .delayed(let minutes):
                return String(format: String(localized: "vehicle.delay.minutesLate"), minutes)
            case .early(let minutes):
                return String(format: String(localized: "vehicle.delay.minutesEarly"), minutes)
            }
        }
    }

    private static let defaultTransitTimeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current

    private static let warsawTimeFormatter = makeTimeFormatter(timeZone: defaultTransitTimeZone)

    private static func makeTimeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    static func delayStatus(for delayMs: Int) -> DelayStatus {
        if delayMs >= 60_000 {
            return .delayed(minutes: delayMs / 60_000)
        } else if delayMs <= -60_000 {
            return .early(minutes: abs(delayMs) / 60_000)
        } else {
            return .onTime
        }
    }

    static func countdownText(estimatedMs: Int64, now: Date) -> String {
        let remainingSeconds = Double(estimatedMs) / 1_000.0 - now.timeIntervalSince1970
        if remainingSeconds <= 30 {
            return String(localized: "vehicle.countdown.lessThanOne")
        }
        let roundedMinutes = max(1, Int((remainingSeconds / 60.0).rounded()))
        return "\(roundedMinutes)"
    }

    static func formattedTime(epochMs: Int64, timeZone: TimeZone = defaultTransitTimeZone) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1_000.0)
        let formatter = (timeZone == defaultTransitTimeZone)
            ? warsawTimeFormatter
            : makeTimeFormatter(timeZone: timeZone)
        return formatter.string(from: date)
    }

    private var headerTitle: String {
        if let headsign = vehicle.headsign, !headsign.isEmpty {
            return headsign
        }
        return vehicle.routeName
    }

    private var headerSubtitle: String? {
        var parts: [String] = []
        if !vehicle.brigade.isEmpty {
            parts.append(String(format: String(localized: "vehicle.brigade"), vehicle.brigade))
        }
        if let model = vehicle.vehicle.model, !model.isEmpty {
            parts.append(model)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var routeAccessibilityDescription: String {
        String(
            format: String(localized: "accessibility.route"),
            vehicle.routeName,
            vehicle.routeType.displayName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, DesignTokens.horizontalPadding)

            ScrollView {
                Group {
                    if vehicle.upcomingStops.isEmpty {
                        emptyStopsSection
                    } else {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            stopsTimeline(now: context.date)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: routeAccessibilityDescription))

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)

                if let headerSubtitle {
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: DesignTokens.compactControlSize, height: DesignTokens.compactControlSize)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("vehicleDetail.close"))
        }
    }

    private func stopsTimeline(now: Date) -> some View {
        let status = Self.delayStatus(for: vehicle.delay)
        let stops = Array(vehicle.upcomingStops.enumerated())

        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(stops, id: \.offset) { index, stop in
                stopRow(
                    stop: stop,
                    index: index,
                    isCurrent: index == 0,
                    status: status,
                    now: now
                )
            }
        }
        .backgroundPreferenceValue(StopTimelineAnchorKey.self) { anchors in
            GeometryReader { geometry in
                if let firstAnchor = anchors[0],
                   let lastIndex = stops.indices.last,
                   let lastAnchor = anchors[lastIndex] {
                    let firstRect = geometry[firstAnchor]
                    let lastRect = geometry[lastAnchor]
                    let startsMidTrip = (vehicle.upcomingStops.first?.sequence ?? 0) > 0
                    let trackWidth: CGFloat = 12
                    let topY = startsMidTrip ? 0 : max(0, firstRect.midY - trackWidth / 2)
                    let bottomY = max(lastRect.midY + trackWidth / 2, geometry.size.height)

                    RoundedRectangle(cornerRadius: trackWidth / 2)
                        .fill(vehicle.displayColor)
                        .frame(width: trackWidth, height: max(trackWidth, bottomY - topY))
                        .position(x: firstRect.midX, y: (topY + bottomY) / 2)
                }
            }
        }
    }

    private func stopRow(
        stop: VehicleUpcomingStop,
        index: Int,
        isCurrent: Bool,
        status: DelayStatus,
        now: Date
    ) -> some View {
        let estimatedArrivalMs = stop.scheduledArrival + Int64(vehicle.delay)
        let estimatedDepartureMs = stop.scheduledDeparture + Int64(vehicle.delay)
        let countdown = Self.countdownText(estimatedMs: estimatedArrivalMs, now: now)
        let displayTime = Self.formattedTime(epochMs: estimatedDepartureMs)

        return GridRow {
            timesColumn(
                stop: stop,
                estimatedArrivalMs: estimatedArrivalMs,
                estimatedDepartureMs: estimatedDepartureMs,
                status: status
            )
            .padding(.vertical, 8)

            timelineNode(isCurrent: isCurrent)
                .frame(width: 28, height: 28)
                .anchorPreference(key: StopTimelineAnchorKey.self, value: .bounds) { [index: $0] }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(isCurrent ? .subheadline.weight(.bold) : .subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(status.localizedText)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(countdown)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("vehicle.countdown.min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(
            format: String(localized: "vehicle.accessibility.stopRow"),
            stop.name,
            displayTime,
            status.localizedText,
            countdown
        )))
    }

    @ViewBuilder
    private func timesColumn(
        stop: VehicleUpcomingStop,
        estimatedArrivalMs: Int64,
        estimatedDepartureMs: Int64,
        status: DelayStatus
    ) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if stop.scheduledArrival == stop.scheduledDeparture {
                if status.isSignificantOffset {
                    Text(Self.formattedTime(epochMs: stop.scheduledDeparture))
                        .font(.caption.monospacedDigit())
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text(Self.formattedTime(epochMs: estimatedDepartureMs))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(status.color)
                } else {
                    Text(Self.formattedTime(epochMs: estimatedDepartureMs))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } else {
                Text(Self.formattedTime(epochMs: estimatedArrivalMs))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(status.isSignificantOffset ? status.color : .primary)
                Text(Self.formattedTime(epochMs: estimatedDepartureMs))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(status.isSignificantOffset ? status.color : .primary)
            }
        }
        .frame(minWidth: 42, alignment: .trailing)
    }

    @ViewBuilder
    private func timelineNode(isCurrent: Bool) -> some View {
        if isCurrent {
            ZStack {
                Circle()
                    .fill(vehicle.displayColor)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2)
                    )

                Image(systemName: vehicle.routeType.systemImageName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(vehicle.contrastingTextColor)
            }
        } else {
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .strokeBorder(vehicle.displayColor, lineWidth: 2.5)
                )
        }
    }

    private var emptyStopsSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("vehicle.stops.empty")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

nonisolated private struct StopTimelineAnchorKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
