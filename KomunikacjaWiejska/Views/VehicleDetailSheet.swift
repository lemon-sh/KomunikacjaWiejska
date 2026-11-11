import SwiftUI

/// Sheet displaying active trip itineraries, live delays, progress, alerts, and fleet metadata.

struct VehicleDetailSheet: View {
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

        var shouldHighlightText: Bool {
            switch self {
            case .delayed, .early: true
            case .onTime: false
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

    static func delayStatus(for delayMs: Int) -> DelayStatus {
        let minutes = delayMs / 60_000
        if minutes > 0 {
            return .delayed(minutes: minutes)
        } else if minutes < 0 {
            return .early(minutes: abs(minutes))
        } else {
            return .onTime
        }
    }

    static func countdownText(estimatedMs: Int64, now: Date = Date()) -> String {
        TransitTimeFormatting.countdownText(estimatedMs: estimatedMs, now: now)
    }

    static func formattedTime(epochMs: Int64, timeZone: TimeZone = .current) -> String {
        TransitTimeFormatting.formattedClockTime(epochMs: epochMs, timeZone: timeZone)
    }

    let detail: ActiveTripDetail
    let timeZone: TimeZone
    let canNavigateBack: Bool
    let isFollowingVehicle: Bool
    let onBack: () -> Void
    let onToggleFollow: () -> Void
    let onDismiss: () -> Void

    init(
        detail: ActiveTripDetail,
        timeZone: TimeZone = .current,
        canNavigateBack: Bool = false,
        isFollowingVehicle: Bool = false,
        onBack: @escaping () -> Void = {},
        onToggleFollow: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.detail = detail
        self.timeZone = timeZone
        self.canNavigateBack = canNavigateBack
        self.isFollowingVehicle = isFollowingVehicle
        self.onBack = onBack
        self.onToggleFollow = onToggleFollow
        self.onDismiss = onDismiss
    }

    /// Convenience initializer for previews and lightweight component tests.
    init(vehicle: VehiclePosition, onDismiss: @escaping () -> Void) {
        self.init(
            detail: ActiveTripDetail(
                city: vehicle.city,
                vehicleId: vehicle.id,
                tripId: vehicle.tripId,
                route: vehicle.route,
                headsign: vehicle.routeLongName,
                brigade: vehicle.brigade,
                livePosition: vehicle,
                isLoading: false
            ),
            onDismiss: onDismiss
        )
    }

    private var routeColor: Color {
        detail.displayRoute?.displayColor ?? .accentColor
    }

    private var routeContrastingColor: Color {
        detail.displayRoute?.contrastingTextColor ?? .white
    }

    private var routeName: String {
        detail.displayRoute?.name ?? "—"
    }

    private var routeSystemImage: String {
        detail.displayRoute?.type.systemImageName ?? RouteType.unknown.systemImageName
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let brigade = detail.displayBrigade, !brigade.isEmpty {
            parts.append(String(format: String(localized: "vehicle.brigade"), brigade))
        }
        if let shortName = detail.tripInfo?.shortName, !shortName.isEmpty {
            parts.append(shortName)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var activeDelayPresentation: TransitDelayPresentation? {
        guard !detail.stopUpdates.isEmpty else { return nil }
        let idx = min(max(detail.currentSequence ?? 0, 0), detail.stopUpdates.count - 1)
        return TransitTimeFormatting.presentation(for: detail.stopUpdates[idx].departure)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusAndMetadataBar
                    if !detail.alerts.isEmpty {
                        alertsSection
                    }
                    itinerarySection
                    if let pairs = detail.tripInfo?.descriptionPairs, !pairs.isEmpty {
                        descriptionFooter(pairs: pairs)
                    }
                }
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.vertical, 14)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            if canNavigateBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("vehicle.back.accessibility"))
            }

            HStack(spacing: 4) {
                Image(systemName: routeSystemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(routeName)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 40, maxHeight: 40)
            .background(routeColor)
            .foregroundStyle(routeContrastingColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(detail.displayHeadsign)
                    .font(.title3.bold())
                    .lineLimit(2)

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if detail.livePosition != nil {
                Button(action: onToggleFollow) {
                    Image(systemName: isFollowingVehicle ? "location.fill" : "location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFollowingVehicle ? .blue : .secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("vehicle.follow.accessibility"))
                .accessibilityAddTraits(isFollowingVehicle ? .isSelected : [])
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("vehicleDetail.close"))
        }
    }

    @ViewBuilder
    private var statusAndMetadataBar: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let delay = activeDelayPresentation {
                        Text(delay.localizedText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delay.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(delay.color.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if let lastPingMs = detail.livePosition?.lastPingMs {
                        Label {
                            Text(TransitTimeFormatting.relativePingDescription(lastPingMs: lastPingMs, now: context.date))
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if let metadata = detail.vehicleMetadata,
                   metadata.model != nil || metadata.carrier != nil {
                    HStack(spacing: 6) {
                        Image(systemName: routeSystemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        let details = [
                            metadata.model,
                            metadata.prodYear.map(String.init),
                            metadata.carrier
                        ].compactMap { $0 }

                        Text(details.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("vehicle.alerts.heading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .textCase(.uppercase)

            ForEach(detail.alerts) { alert in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(alert.title)
                            .font(.caption.weight(.semibold))
                    }
                    if !alert.description.isEmpty {
                        Text(alert.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var itinerarySection: some View {
        let stops = detail.itinerary?.stops ?? []
        if detail.isLoading && stops.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("map.loading.initial")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else if let errorMessage = detail.errorMessage, stops.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else if stops.isEmpty {
            Text("vehicle.stops.empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, itineraryStop in
                        let update = index < detail.stopUpdates.count ? detail.stopUpdates[index] : nil
                        TripTimelineRow(
                            itineraryStop: itineraryStop,
                            update: update,
                            index: index,
                            totalCount: stops.count,
                            sequence: detail.currentSequence,
                            percentTraveled: detail.livePosition?.percentTraveled,
                            routeColor: routeColor,
                            routeContrastingColor: routeContrastingColor,
                            routeSystemImage: routeSystemImage,
                            timeZone: timeZone,
                            now: context.date
                        )
                    }
                }
            }
        }
    }

    private func descriptionFooter(pairs: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .padding(.vertical, 4)

            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                if pair.count >= 2 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pair[0])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(pair[1])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let first = pair.first {
                    Text(first)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TripTimelineRow: View {
    let itineraryStop: ItineraryStop
    let update: TripStopUpdate?
    let index: Int
    let totalCount: Int
    let sequence: Int?
    let percentTraveled: Double?
    let routeColor: Color
    let routeContrastingColor: Color
    let routeSystemImage: String
    let timeZone: TimeZone
    let now: Date

    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == totalCount - 1 }

    private var hasDeparted: Bool {
        guard let update else { return false }
        if update.departure.isCancelled { return true }
        if let sequence {
            return index < sequence
        }
        return update.departure.estimatedMs < Int64(now.timeIntervalSince1970 * 1_000.0)
    }

    private var showsLiveVehicleOnSegment: Bool {
        !isFirst && sequence == index && percentTraveled != nil
    }

    private var clampedPercentFraction: CGFloat {
        let value = (percentTraveled ?? 0) / 100.0
        return CGFloat(min(max(value, 0.0), 1.0))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            timeColumn
                .frame(width: 48, alignment: .trailing)

            trackColumn
                .frame(width: 24)

            stopDetailsColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)

            countdownColumn
        }
        .opacity(hasDeparted ? 0.65 : 1.0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var timeColumn: some View {
        if let update {
            let arrivalText = TransitTimeFormatting.formattedClockTime(epochMs: update.arrival.estimatedMs, timeZone: timeZone)
            let departureText = TransitTimeFormatting.formattedClockTime(epochMs: update.departure.estimatedMs, timeZone: timeZone)
            let presentation = TransitTimeFormatting.presentation(for: update.departure)
            let scheduledText = TransitTimeFormatting.formattedClockTime(epochMs: update.departure.scheduledMs, timeZone: timeZone)

            VStack(alignment: .trailing, spacing: 1) {
                if arrivalText != departureText {
                    Text(arrivalText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(departureText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(presentation.shouldHighlightText ? presentation.color : .primary)
                } else if presentation.shouldStrikeScheduledTime {
                    Text(scheduledText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .strikethrough()
                    if !update.departure.isCancelled {
                        Text(departureText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(presentation.color)
                    }
                } else {
                    Text(departureText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(presentation.shouldHighlightText ? presentation.color : .primary)
                }
            }
        }
    }

    private var trackColumn: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(isFirst ? .clear : routeColor)
                    .frame(width: 3)

                if showsLiveVehicleOnSegment {
                    GeometryReader { proxy in
                        Image(systemName: routeSystemImage)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(routeContrastingColor)
                            .frame(width: 20, height: 20)
                            .background(routeColor)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 1.5)
                            )
                            .position(
                                x: proxy.size.width / 2,
                                y: max(10, proxy.size.height * clampedPercentFraction)
                            )
                            .animation(.easeInOut(duration: 0.5), value: clampedPercentFraction)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Circle()
                .fill(hasDeparted ? routeColor : Color(.systemBackground))
                .overlay(
                    Circle()
                        .stroke(routeColor, lineWidth: 2.5)
                )
                .frame(width: 11, height: 11)

            Rectangle()
                .fill(isLast ? .clear : routeColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
    }

    private var stopDetailsColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(itineraryStop.stop.name)
                    .font(.subheadline.weight((sequence == index && !hasDeparted) ? .bold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !itineraryStop.stop.code.isEmpty {
                    Text(itineraryStop.stop.code)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            let platform = update?.platform ?? itineraryStop.platform
            let track = update?.track
            if platform != nil || track != nil || itineraryStop.isOnDemand || itineraryStop.isBoardingForbidden {
                HStack(spacing: 6) {
                    if let platform {
                        Text(String(format: String(localized: "stopDetail.platform"), platform))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let track {
                        Text(String(format: String(localized: "vehicle.stop.track"), track))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if itineraryStop.isOnDemand {
                        Label("vehicle.stop.onDemand", systemImage: "hand.raised.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if itineraryStop.isBoardingForbidden {
                        Label("vehicle.stop.noBoarding", systemImage: "arrow.down.to.line")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var countdownColumn: some View {
        if let update, !hasDeparted, !update.departure.isCancelled {
            let minutes = TransitTimeFormatting.minutesRemaining(estimatedMs: update.departure.estimatedMs, now: now)
            let presentation = TransitTimeFormatting.presentation(for: update.departure)
            if minutes >= 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(TransitTimeFormatting.countdownText(estimatedMs: update.departure.estimatedMs, now: now))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(presentation.shouldHighlightText ? presentation.color : .primary)

                    Text("vehicle.countdown.min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
