import MapKit
import SwiftUI

struct TransitMapView: View {
    @State private var viewModel: MapViewModel
    @State private var activeDetail: ActiveMapDetail?
    private var locationManager: any LocationProviding
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapScope

    init(
        viewModel: MapViewModel? = nil,
        locationManager: (any LocationProviding)? = nil
    ) {
        _viewModel = State(initialValue: viewModel ?? MapViewModel())
        self.locationManager = locationManager ?? LocationManager.shared
    }

    /// Keeps the detail sheet presented while only its content swaps. Binding
    /// the sheet to an active detail instead of an item prevents dismiss/re-present
    /// thrashing and preserves chosen presentation detents.
    private var isDetailSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.selection != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.selection = nil
                }
            }
        )
    }

    private var currentDetailFromSelection: ActiveMapDetail? {
        if let stopID = viewModel.selectedStopID, let stop = viewModel.cachedStop(for: stopID) {
            return .stop(stop)
        } else if let vehicleID = viewModel.selectedVehicleID, let vehicle = viewModel.cachedVehicle(for: vehicleID) {
            return .vehicle(vehicle)
        }
        return nil
    }

    private func selectStop(_ stop: Stop) {
        activeDetail = .stop(stop)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            viewModel.selection = .stop(stop.id)
        }
    }

    private func selectVehicle(_ vehicle: VehiclePosition) {
        activeDetail = .vehicle(vehicle)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            viewModel.selection = .vehicle(vehicle.id)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(
                position: Binding(
                    get: { viewModel.cameraPosition },
                    set: { viewModel.setCameraPositionFromGesture($0) }
                ),
                selection: $viewModel.selection,
                scope: mapScope
            ) {
                UserAnnotation()

                if viewModel.areStopsVisible {
                    ForEach(viewModel.stops) { stop in
                        Annotation(
                            viewModel.areStopTitlesVisible ? stop.displayName : "",
                            coordinate: stop.coordinate,
                            anchor: .center
                        ) {
                            StopAnnotationContent(
                                stop: stop,
                                viewModel: viewModel,
                                onSelect: { selectStop(stop) }
                            )
                        }
                        .annotationTitles(viewModel.areStopTitlesVisible ? .visible : .hidden)
                        .tag(MapViewModel.FeatureSelection.stop(stop.id))
                    }
                }

                if viewModel.isVehiclesVisible {
                    ForEach(viewModel.vehicles) { vehicle in
                        Annotation(
                            "",
                            coordinate: vehicle.coordinate,
                            anchor: .center
                        ) {
                            VehicleAnnotationContent(
                                vehicle: vehicle,
                                viewModel: viewModel,
                                onSelect: { selectVehicle(vehicle) }
                            )
                        }
                        .annotationTitles(.hidden)
                        .tag(MapViewModel.FeatureSelection.vehicle(vehicle.id))
                    }
                }
            }
            .mapStyle(viewModel.selectedMapMode.mapStyle)
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.handleCameraChange(to: context)
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            TopChromeView(viewModel: viewModel, mapScope: mapScope)
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
            viewModel.startVehiclePolling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // No network/GPS activity while the app is in the background.
            if newPhase == .background {
                viewModel.saveCameraPosition()
                viewModel.pauseForBackground()
                locationManager.stopUpdatingLocation()
            } else if newPhase == .active {
                locationManager.requestWhenInUseAuthorization()
                viewModel.loadStopsForSelectedCity()
                viewModel.startVehiclePolling()
            }
        }
        .onChange(of: viewModel.selection) { _, newSelection in
            switch newSelection {
            case .stop(let id):
                if let stop = viewModel.cachedStop(for: id) {
                    activeDetail = .stop(stop)
                }
            case .vehicle(let id):
                if let vehicle = viewModel.cachedVehicle(for: id) {
                    activeDetail = .vehicle(vehicle)
                }
            case nil:
                break
            }
        }
        .onChange(of: viewModel.vehicles) { _, newVehicles in
            if case .vehicle(let vehicle) = activeDetail,
               let updated = newVehicles.first(where: { $0.id == vehicle.id }) {
                activeDetail = .vehicle(updated)
            }
        }
        .sheet(isPresented: isDetailSheetPresented) {
            if let detail = activeDetail ?? currentDetailFromSelection {
                switch detail {
                case .stop(let stop):
                    StopDetailSheet(stop: stop) {
                        viewModel.selection = nil
                    }
                    .presentationDetents([.height(DesignTokens.sheetSmallDetentHeight), .medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                case .vehicle(let vehicle):
                    VehicleDetailSheet(vehicle: vehicle) {
                        viewModel.selection = nil
                    }
                    .presentationDetents([.height(DesignTokens.vehicleSheetSmallDetentHeight), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(DesignTokens.vehicleSheetSmallDetentHeight)))
                }
            }
        }
    }

}

// MARK: - Top chrome

/// Isolated subview for top controls and notifications.
/// Isolating these controls prevents status and error changes from invalidating
/// the parent `TransitMapView.body` and triggering expensive MapKit annotation diffing.
private struct TopChromeView: View {
    @Bindable var viewModel: MapViewModel
    let mapScope: Namespace.ID

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                cityPickerButton
                Spacer()
                trailingControls
            }
            statusCapsule
            if let suggestedCity = viewModel.suggestedCity {
                regionSuggestionCapsule(for: suggestedCity)
            }
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
        .sheet(isPresented: $viewModel.isShowingCityPicker) {
            CityPickerSheet(selectedCity: viewModel.selectedCity) { city in
                viewModel.selectCity(city)
            }
        }
    }

    private var trailingControls: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.controlSpacing) {
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
                .frame(minWidth: DesignTokens.controlSize, minHeight: DesignTokens.controlSize)
                .contentShape(Circle())
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
                if viewModel.isRetryableError {
                    Button {
                        viewModel.loadStopsForSelectedCity()
                    } label: {
                        Text("map.error.retry")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private func regionSuggestionCapsule(for city: City) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.switchToSuggestedCity()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption.weight(.semibold))
                    Text(String(format: String(localized: "map.suggestion.switchCity"), city.name))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.dismissSuggestedCity()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("map.suggestion.dismiss"))
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
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

private enum ActiveMapDetail: Equatable {
    case stop(Stop)
    case vehicle(VehiclePosition)
}

/// Reads the selection and camera state on the annotation's own view body so
/// Observation invalidates the marker immediately. Reading the same values in
/// `Annotation`'s escaping content closure is not tracked by SwiftUI, which
/// left markers stale until the next camera update.
/// `.onTapGesture` eliminates the ~350ms MapKit gesture recognizer delay when tapping.
private struct StopAnnotationContent: View {
    let stop: Stop
    let viewModel: MapViewModel
    let onSelect: () -> Void

    var body: some View {
        let heading: Double = stop.bearing != nil ? viewModel.currentHeading : 0
        StopMarkerView(
            stop: stop,
            isSelected: viewModel.selectedStopID == stop.id,
            heading: heading
        )
        .equatable()
        .onTapGesture {
            onSelect()
        }
    }
}

private struct VehicleAnnotationContent: View {
    let vehicle: VehiclePosition
    let viewModel: MapViewModel
    let onSelect: () -> Void

    var body: some View {
        let isCompact = viewModel.isVehicleCompactDisplayMode
        let heading: Double = (!isCompact && vehicle.bearing != nil) ? viewModel.currentHeading : 0
        VehicleMarkerView(
            vehicle: vehicle,
            isSelected: viewModel.selectedVehicleID == vehicle.id,
            isCompact: isCompact,
            heading: heading
        )
        .equatable()
        .onTapGesture {
            onSelect()
        }
    }
}
