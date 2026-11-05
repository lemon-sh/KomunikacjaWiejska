import MapKit
import SwiftUI

public struct TransitMapView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapScope

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            Map(
                position: $viewModel.cameraPosition,
                selection: $viewModel.selectedStopID,
                scope: mapScope
            ) {
                UserAnnotation()

                ForEach(viewModel.stops) { stop in
                    Annotation(stop.displayName, coordinate: stop.coordinate, anchor: .center) {
                        StopMarkerView(
                            stop: stop,
                            isSelected: viewModel.selectedStopID == stop.id,
                            isCompact: viewModel.isCompactDisplayMode
                        )
                    }
                    .tag(stop.id)
                }
            }
            .mapStyle(viewModel.selectedMapMode.mapStyle)
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.handleCameraChange(to: context)
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            topChrome
        }
        // Bottom Right: Apple Maps Map Style + Location Combo Capsule
        .overlay(alignment: .bottomTrailing) {
            MapControlsComboView(
                viewModel: viewModel,
                locationManager: locationManager
            )
            .padding(.trailing, DesignTokens.horizontalPadding)
            .padding(.bottom, DesignTokens.bottomPadding)
        }
        .mapScope(mapScope)
        .onAppear {
            locationManager.requestWhenInUseAuthorization()
        }
        .task {
            viewModel.loadStopsForSelectedCity()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // No network/GPS activity while the app is in the background.
            if newPhase == .background {
                viewModel.pauseForBackground()
                locationManager.stopUpdatingLocation()
            } else if newPhase == .active {
                locationManager.requestWhenInUseAuthorization()
                viewModel.loadStopsForSelectedCity()
            }
        }
        .sheet(item: Binding(
            get: { viewModel.selectedStop },
            set: { newValue in
                // Scene-dismiss or close button both funnel through here so
                // the ID is cleared exactly once.
                viewModel.selectedStopID = newValue?.id
            }
        )) { stop in
            StopDetailSheet(stop: stop) {
                viewModel.selectedStopID = nil
            }
            .presentationDetents([.height(240), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .height(240)))
        }
        .sheet(isPresented: $viewModel.isShowingCityPicker) {
            CityPickerSheet(selectedCity: $viewModel.selectedCity)
        }
    }

    // MARK: - Top chrome

    /// One top-aligned stack instead of a fixed spacer: controls sit below the
    /// safe area, and the status capsule flows underneath them without a magic
    /// 52 pt offset. Works with the Dynamic Island and in landscape.
    private var topChrome: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                cityPickerButton
                Spacer()
                trailingControls
            }
            statusCapsule
        }
        .padding(.horizontal, DesignTokens.horizontalPadding)
        .padding(.top, DesignTokens.topPadding)
    }

    private var cityPickerButton: some View {
        Button {
            viewModel.isShowingCityPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tram.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.headline)
                Text(viewModel.selectedCity.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(Text("map.control.cityPicker"))
        .accessibilityValue(Text(viewModel.selectedCity.name))
    }

    private var trailingControls: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.controlSpacing) {
            Button {
                viewModel.refreshStopsForSelectedCity()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: DesignTokens.controlSize, height: DesignTokens.controlSize)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("map.control.refresh"))

            // The compass is the native `MapCompass`; it deliberately keeps
            // Apple's own appearance and animations.
            MapCompass(scope: mapScope)

            // 2D Button: appears when map pitch is tilted in 3D
            if viewModel.isPitched3D {
                Button {
                    viewModel.resetPitchTo2D()
                } label: {
                    Text("map.control.2d")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: DesignTokens.compactControlSize, height: DesignTokens.compactControlSize)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("map.control.2d.accessibility"))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var statusCapsule: some View {
        if viewModel.isLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingMessage)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
        } else if let error = viewModel.errorMessage {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    viewModel.refreshStopsForSelectedCity()
                } label: {
                    Text("map.error.retry")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private var loadingMessage: String {
        switch viewModel.loadingPhase {
        case .refresh:
            return String(localized: "map.loading.refresh")
        case .citySwitch:
            return String(localized: "map.loading.citySwitch")
        case .initial, .none:
            return String(localized: "map.loading.initial")
        }
    }
}
