import SwiftUI
import UIKit

struct MapControlsComboView: View {
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

    init(viewModel: MapViewModel, locationManager: any LocationProviding) {
        self.viewModel = viewModel
        self.locationManager = locationManager
    }

    var body: some View {
        // `glassEffectUnion` groups the two buttons into one native capsule.
        // Grouping is not expressible with `.buttonStyle(.glass)` alone, so the
        // glass modifiers are used deliberately here and documented rather
        // than mixed for equivalent controls.
        GlassEffectContainer {
            VStack(spacing: 0) {
                Button {
                    viewModel.toggleMapMode()
                } label: {
                    Image(systemName: viewModel.selectedMapMode == .satellite ? "map" : "globe")
                        .frame(width: DesignTokens.controlSize, height: DesignTokens.controlSize)
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
