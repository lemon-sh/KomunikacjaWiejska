import SwiftUI

/// Sheet displaying hydrated stop metadata, exits, and live `stops/{id}/stream` departures.

private struct RouteBadgeView: View {
    let route: StopRoute

    private var badgeColor: Color {
        route.displayColor
    }

    private var textColor: Color {
        route.contrastingTextColor
    }

    private var accessibilityText: String {
        String(
            format: String(localized: "accessibility.route"),
            route.type.displayName,
            route.name,
            route.longName
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: route.type.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12, height: 12)
            Text(route.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 32, minHeight: 24)
        .background(badgeColor)
        .foregroundStyle(textColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

struct StopDetailSheet: View {
    let stop: Stop
    let departures: [StopDeparture]
    let isLoadingDepartures: Bool
    let errorMessage: String?
    let timeZone: TimeZone
    let onSelectDeparture: (StopDeparture) -> Void
    let onDismiss: () -> Void

    init(
        stop: Stop,
        departures: [StopDeparture] = [],
        isLoadingDepartures: Bool = false,
        errorMessage: String? = nil,
        timeZone: TimeZone = .current,
        onSelectDeparture: @escaping (StopDeparture) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.stop = stop
        self.departures = departures
        self.isLoadingDepartures = isLoadingDepartures
        self.errorMessage = errorMessage
        self.timeZone = timeZone
        self.onSelectDeparture = onSelectDeparture
        self.onDismiss = onDismiss
    }

    private var directionSubtitle: String {
        String(format: String(localized: "stopDetail.direction"), stop.direction)
    }

    private var routesSectionTitle: String {
        String(
            format: String(localized: "stopDetail.routesHeading"),
            Int64(stop.routes.count)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    departuresSection
                    routesSection
                    if !stop.entrances.isEmpty {
                        entrancesSection
                    }
                }
                .padding(.horizontal, DesignTokens.horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stop.primaryVehicleType.systemImageName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(stop.primaryVehicleType.defaultColor)
                .frame(width: 40, height: 40)
                .background(stop.primaryVehicleType.defaultColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stop.name)
                        .font(.title3.bold())
                        .lineLimit(2)

                    if !stop.code.isEmpty {
                        Text(stop.code)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if !stop.direction.isEmpty {
                    Text(directionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("stopDetail.close"))
        }
    }

    private var departuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("stopDetail.departuresHeading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isLoadingDepartures && departures.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("stopDetail.loadingDepartures")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let errorMessage, departures.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if departures.isEmpty {
                Text("stopDetail.noDepartures")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    VStack(spacing: 0) {
                        ForEach(Array(departures.enumerated()), id: \.element.id) { index, departure in
                            StopDepartureRowView(
                                departure: departure,
                                timeZone: timeZone,
                                now: context.date
                            ) {
                                onSelectDeparture(departure)
                            }
                            if index < departures.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routesSectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if stop.routes.isEmpty {
                Text("stopDetail.noRoutes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(stop.routes) { route in
                        RouteBadgeView(route: route)
                    }
                }
            }
        }
    }

    private var entrancesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("stopDetail.entrancesHeading")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(stop.entrances) { entrance in
                HStack(spacing: 8) {
                    Image(systemName: "door.left.hand.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(entrance.name)
                        .font(.subheadline)
                }
            }
        }
    }
}

private struct StopDepartureRowView: View {
    let departure: StopDeparture
    let timeZone: TimeZone
    let now: Date
    let onTap: () -> Void

    private var route: StopRoute {
        departure.trip.route
    }

    private var timeUpdate: StopTimeUpdate {
        departure.departure
    }

    private var delayPresentation: TransitDelayPresentation {
        TransitTimeFormatting.presentation(for: timeUpdate)
    }

    private var scheduledTimeText: String {
        TransitTimeFormatting.formattedClockTime(epochMs: timeUpdate.scheduledMs, timeZone: timeZone)
    }

    private var estimatedTimeText: String {
        TransitTimeFormatting.formattedClockTime(epochMs: timeUpdate.estimatedMs, timeZone: timeZone)
    }

    private var shouldShowCountdown: Bool {
        !timeUpdate.isCancelled && timeUpdate.estimatedMs >= Int64(now.timeIntervalSince1970 * 1_000.0) - 30_000
    }

    private var countdownText: String {
        TransitTimeFormatting.countdownText(estimatedMs: timeUpdate.estimatedMs, now: now)
    }

    private var accessibilityText: String {
        String(
            format: String(localized: "stopDetail.accessibility.departureRow"),
            route.name,
            departure.trip.headsign,
            delayPresentation.localizedText
        )
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                RouteBadgeView(route: route)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(departure.trip.headsign)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let brigade = departure.trip.brigade, !brigade.isEmpty {
                            Text("/ \(brigade)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 5) {
                        if departure.vehicle != nil && timeUpdate.isLive {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(delayPresentation.color)
                                .accessibilityHidden(true)
                        }

                        Text(delayPresentation.localizedText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(delayPresentation.color)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if delayPresentation.shouldStrikeScheduledTime {
                            Text(scheduledTimeText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .strikethrough()

                            if !timeUpdate.isCancelled {
                                Text(estimatedTimeText)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Text(estimatedTimeText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if let platform = timeUpdate.platform, !platform.isEmpty {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: String(localized: "stopDetail.platform"), platform))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                if shouldShowCountdown {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(countdownText)
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(delayPresentation.shouldHighlightText ? delayPresentation.color : .primary)
                        Text("vehicle.countdown.min")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .opacity(timeUpdate.isCancelled ? 0.65 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
