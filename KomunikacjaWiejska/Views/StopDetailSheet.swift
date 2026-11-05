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

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: route.type.systemImageName)
                .font(.system(size: 10, weight: .bold))
            Text(route.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

public struct StopDetailSheet: View {
    public let stop: Stop
    public let onDismiss: () -> Void

    public init(stop: Stop, onDismiss: @escaping () -> Void) {
        self.stop = stop
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Stop Name, Code badge & Close button
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: stop.primaryVehicleType.systemImageName)
                    .font(.title2)
                    .foregroundStyle(stop.primaryVehicleType.defaultColor)
                    .padding(8)
                    .background(stop.primaryVehicleType.defaultColor.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stop.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)

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
                            Text("Kierunek: \(stop.direction)")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Routes section
            if !stop.routes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linie na tym przystanku (\(stop.routes.count))")
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
            } else {
                Text("Brak przypisanych linii dla tego słupka.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }
}
