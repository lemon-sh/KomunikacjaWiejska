import Foundation
import SwiftUI

public struct RouteBadgeView: View {
    public let route: StopRoute

    public init(route: StopRoute) {
        self.route = route
    }

    private var badgeColor: Color {
        if route.color.isEmpty {
            return route.type.defaultColor
        }
        return Color(hex: route.color, fallback: route.type.defaultColor)
    }

    private var accessibilityDescription: String {
        String(
            format: String(localized: "accessibility.route"),
            route.name,
            route.type.displayName
        )
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: route.type.systemImageName)
                .font(.caption2.weight(.bold))
                .frame(width: 14, height: 14)
            Text(route.name)
                .font(.system(.caption, design: .rounded).weight(.bold))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(badgeColor)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
    }
}

public struct StopDetailSheet: View {
    public let stop: Stop
    public let onDismiss: () -> Void

    public init(stop: Stop, onDismiss: @escaping () -> Void) {
        self.stop = stop
        self.onDismiss = onDismiss
    }

    private var directionText: String {
        String(format: String(localized: "stopDetail.direction"), stop.direction)
    }

    private var routesHeading: String {
        String(
            format: String(localized: "stopDetail.routesHeading"),
            Int64(stop.routes.count)
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                routesSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: stop.primaryVehicleType.systemImageName)
                .font(.title2)
                .foregroundStyle(stop.primaryVehicleType.defaultColor)
                .frame(width: 40, height: 40)
                .background(stop.primaryVehicleType.defaultColor.opacity(0.15))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stop.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !stop.code.isEmpty {
                        Text(stop.code)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if !stop.direction.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.forward")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(directionText)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .accessibilityLabel(Text("stopDetail.close"))
        }
    }

    @ViewBuilder
    private var routesSection: some View {
        if stop.routes.isEmpty {
            Text("stopDetail.noRoutes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: routesHeading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(stop.routes) { route in
                            RouteBadgeView(route: route)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
