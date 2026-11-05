import SwiftUI

@MainActor
public struct MapControlsComboView: View {
    @Bindable var viewModel: MapViewModel
    @Namespace private var namespace
    var locationManager: LocationManager
    @State private var isShowingLocationAlert = false
    @Environment(\.openURL) private var openURL

    public init(viewModel: MapViewModel, locationManager: LocationManager) {
        self.viewModel = viewModel
        self.locationManager = locationManager
    }

    public var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                Button {
                    viewModel.isShowingMapModes.toggle()
                } label: {
                    Image(systemName: "map").frame(width: 44, height: 44)
                }
                .popover(isPresented: $viewModel.isShowingMapModes, arrowEdge: .trailing) {
                    MapModesPopoverView(
                        selectedMode: $viewModel.selectedMapMode,
                        isPresented: $viewModel.isShowingMapModes
                    )
                    .presentationCompactAdaptation(.popover)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(.primary)
                .glassEffectUnion(id: "mainCapsule", namespace: namespace)

                Button {
                    handleLocationTap()
                } label: {
                    Image(systemName: viewModel.isTrackingUser ? "location.fill" : "location").frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(.primary)
                .glassEffectUnion(id: "mainCapsule", namespace: namespace)
            }
        }
        .alert("Włącz lokalizację w Ustawieniach", isPresented: $isShowingLocationAlert) {
            Button("Otwórz Ustawienia", action: openAppSettings)
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Dostęp do lokalizacji jest zablokowany, więc nie można wyświetlić Twojego położenia na mapie.")
        }
    }

    private func handleLocationTap() {
        switch locationManager.authorizationState {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized:
            if let coordinate = locationManager.userLocation?.coordinate {
                viewModel.centerOnUserLocation(coordinate: coordinate)
            } else {
                // No fix yet: request a one-shot location update.
                locationManager.requestLocationUpdate()
            }
        case .denied, .servicesDisabled:
            // Requesting again can never succeed; offer the Settings deep link.
            isShowingLocationAlert = true
        }
    }

    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            openURL(settingsURL)
        }
    }
}

@MainActor
public struct MapModesPopoverView: View {
    @Binding var selectedMode: MapMode
    @Binding var isPresented: Bool

    public init(selectedMode: Binding<MapMode>, isPresented: Binding<Bool>) {
        self._selectedMode = selectedMode
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Map Modes")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            HStack(spacing: 18) {
                MapModeCardView(
                    mode: .explore,
                    isSelected: selectedMode == .explore
                ) {
                    selectedMode = .explore
                    isPresented = false
                }

                MapModeCardView(
                    mode: .satellite,
                    isSelected: selectedMode == .satellite
                ) {
                    selectedMode = .satellite
                    isPresented = false
                }
            }

            Text("© OpenStreetMap and other data providers")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

@MainActor
private struct MapModeCardView: View {
    let mode: MapMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if mode == .explore {
                        ExploreThumbnailView()
                    } else {
                        SatelliteThumbnailView()
                    }
                }
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                        .padding(-2)
                )

                Text(mode.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Stylized Explore vector thumbnail resembling Apple Maps standard view.
private struct ExploreThumbnailView: View {
    var body: some View {
        ZStack {
            // Dark road / building terrain background
            Color(red: 0.16, green: 0.19, blue: 0.23)

            // Park green patch
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.14, green: 0.30, blue: 0.24))
                .frame(width: 44, height: 32)
                .offset(x: -20, y: -18)

            // Diagonal primary avenue
            Path { path in
                path.move(to: CGPoint(x: 20, y: 0))
                path.addLine(to: CGPoint(x: 75, y: 82))
            }
            .stroke(Color(red: 0.26, green: 0.31, blue: 0.38), style: StrokeStyle(lineWidth: 18, lineCap: .round))

            // Cross street
            Path { path in
                path.move(to: CGPoint(x: 0, y: 45))
                path.addLine(to: CGPoint(x: 82, y: 25))
            }
            .stroke(Color(red: 0.22, green: 0.26, blue: 0.32), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // Crosswalk dashes
            Path { path in
                path.move(to: CGPoint(x: 32, y: 22))
                path.addLine(to: CGPoint(x: 48, y: 44))
            }
            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))

            // Colored transit indicator dots
            Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: -8, y: -12)
            Circle().fill(Color.yellow).frame(width: 5, height: 5).offset(x: 2, y: -22)
            Circle().fill(Color.red).frame(width: 5, height: 5).offset(x: -16, y: 18)
            Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: -6, y: 26)
        }
    }
}

/// Stylized Satellite vector thumbnail resembling aerial imagery.
private struct SatelliteThumbnailView: View {
    var body: some View {
        ZStack {
            // Earth / vegetation dark green base
            Color(red: 0.32, green: 0.42, blue: 0.27)

            // Farmland / grass patch
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 55, y: 0))
                path.addLine(to: CGPoint(x: 30, y: 82))
                path.addLine(to: CGPoint(x: 0, y: 82))
                path.closeSubpath()
            }
            .fill(Color(red: 0.42, green: 0.50, blue: 0.30))

            // Winding paved highway
            Path { path in
                path.move(to: CGPoint(x: 10, y: 82))
                path.addCurve(to: CGPoint(x: 82, y: 15), control1: CGPoint(x: 30, y: 60), control2: CGPoint(x: 45, y: 35))
            }
            .stroke(Color(red: 0.65, green: 0.64, blue: 0.60), style: StrokeStyle(lineWidth: 12, lineCap: .round))

            // Small highway shoulder stripe
            Path { path in
                path.move(to: CGPoint(x: 10, y: 82))
                path.addCurve(to: CGPoint(x: 82, y: 15), control1: CGPoint(x: 30, y: 60), control2: CGPoint(x: 45, y: 35))
            }
            .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            // Building roofs
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.82, green: 0.80, blue: 0.74))
                .frame(width: 14, height: 9)
                .rotationEffect(.degrees(12))
                .offset(x: 20, y: -20)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.74, green: 0.70, blue: 0.64))
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(12))
                .offset(x: 24, y: -8)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 0.86, green: 0.84, blue: 0.80))
                .frame(width: 12, height: 10)
                .offset(x: -18, y: 22)
        }
    }
}
