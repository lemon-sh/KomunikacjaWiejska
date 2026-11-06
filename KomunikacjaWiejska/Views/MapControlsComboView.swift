import SwiftUI
import UIKit

public struct MapControlsComboView: View {
    @Bindable var viewModel: MapViewModel
    @Namespace private var namespace
    var locationManager: any LocationProviding
    @State private var locationAlert: LocationAlert?
    @Environment(\.openURL) private var openURL

    private enum LocationAlert: Hashable, Identifiable {
        case settings
        case unavailable

        var id: Self { self }
    }

    public init(viewModel: MapViewModel, locationManager: any LocationProviding) {
        self.viewModel = viewModel
        self.locationManager = locationManager
    }

    public var body: some View {
        // `glassEffectUnion` groups the two buttons into one native capsule.
        // Grouping is not expressible with `.buttonStyle(.glass)` alone, so the
        // glass modifiers are used deliberately here and documented rather
        // than mixed for equivalent controls.
        GlassEffectContainer {
            VStack(spacing: 0) {
                Button {
                    viewModel.isShowingMapModes.toggle()
                } label: {
                    Image(systemName: "map")
                        .frame(width: DesignTokens.controlSize, height: DesignTokens.controlSize)
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
                .accessibilityLabel(Text("map.control.mapModes"))
                .accessibilityValue(Text(viewModel.selectedMapMode.displayName))

                Button {
                    handleLocationTap()
                } label: {
                    Image(systemName: viewModel.isTrackingUser ? "location.fill" : "location")
                        .frame(width: DesignTokens.controlSize, height: DesignTokens.controlSize)
                }
                .disabled(locationManager.isRequestingLocation)
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(.primary)
                .glassEffectUnion(id: "mainCapsule", namespace: namespace)
                .accessibilityLabel(Text("map.control.location"))
                .accessibilityAddTraits(viewModel.isTrackingUser ? .isSelected : [])
            }
        }
        .alert(
            locationAlert == .settings ? Text("location.alert.title") : Text("location.error.title"),
            isPresented: Binding(
                get: { locationAlert != nil },
                set: { if !$0 { locationAlert = nil } }
            ),
            presenting: locationAlert
        ) { alert in
            switch alert {
            case .settings:
                Button("location.alert.openSettings", action: openAppSettings)
                Button("location.alert.cancel", role: .cancel) { locationAlert = nil }
            case .unavailable:
                Button("location.error.ok", role: .cancel) { locationAlert = nil }
            }
        } message: { alert in
            switch alert {
            case .settings:
                Text("location.alert.message")
            case .unavailable:
                Text("location.error.message")
            }
        }
    }

    private func handleLocationTap() {
        guard !locationManager.isRequestingLocation else { return }
        switch locationManager.authorizationState {
        case .notDetermined, .authorized:
            // A single async request covers both cases: it waits for the
            // authorization prompt when needed, then centers the camera once
            // the one-shot fix arrives.
            Task {
                do {
                    let location = try await locationManager.requestCurrentLocation()
                    viewModel.centerOnUserLocation(coordinate: location.coordinate)
                } catch LocationError.denied {
                    locationAlert = .settings
                } catch {
                    locationAlert = .unavailable
                }
            }
        case .denied:
            // Requesting again can never succeed; offer the Settings deep link.
            locationAlert = .settings
        }
    }

    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            openURL(settingsURL)
        }
    }
}

public struct MapModesPopoverView: View {
    @Binding var selectedMode: MapMode
    @Binding var isPresented: Bool

    public init(selectedMode: Binding<MapMode>, isPresented: Binding<Bool>) {
        self._selectedMode = selectedMode
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("map.modes.title")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            HStack(spacing: 18) {
                ForEach(MapMode.allCases) { mode in
                    MapModeCardView(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        selectedMode = mode
                        isPresented = false
                    }
                }
            }

            Text("map.modes.attribution")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

private struct MapModeCardView: View {
    let mode: MapMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.badgeCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: mode.previewColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: mode.previewSymbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: DesignTokens.modePreviewSize, height: DesignTokens.modePreviewSize)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.badgeCornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

                Text(mode.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension MapMode {
    var previewSymbol: String {
        switch self {
        case .explore: "map.fill"
        case .satellite: "globe.americas.fill"
        }
    }

    var previewColors: [Color] {
        switch self {
        case .explore:
            return [Color(red: 0.16, green: 0.42, blue: 0.32), Color(red: 0.30, green: 0.62, blue: 0.44)]
        case .satellite:
            return [Color(red: 0.16, green: 0.24, blue: 0.36), Color(red: 0.36, green: 0.52, blue: 0.62)]
        }
    }
}
