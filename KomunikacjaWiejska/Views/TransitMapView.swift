import CoreLocation
import MapKit
import SwiftUI

/// Primary map canvas wiring SSE map streams, detail isolation, and Stop/Trip sheet navigation.

struct TransitMapView: View {
    @State private var viewModel: MapViewModel
    private var locationManager: any LocationProviding
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var mapScope

    init(
        viewModel: MapViewModel? = nil,
        locationManager: (any LocationProviding)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel ?? MapViewModel())
        self.locationManager = locationManager ?? LocationManager.shared
    }

    private var isDetailSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.activeStopDetail != nil || viewModel.activeTripDetail != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.selection = nil
                }
            }
        )
    }

    private func selectStop(_ stop: Stop) {
        viewModel.selection = .stop(stop.id)
    }

    private func selectVehicle(_ vehicle: VehiclePosition) {
        viewModel.selection = .vehicle(vehicle.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(
                position: Binding(
                    get: { viewModel.cameraPosition },
                    set: { viewModel.setCameraPositionFromGesture($0) }
                ),
                interactionModes: .all,
                selection: $viewModel.selection,
                scope: mapScope
            ) {
                UserAnnotation()

                if viewModel.displayedRouteCoordinates.count >= 2 {
                    MapPolyline(coordinates: viewModel.displayedRouteCoordinates)
                        .stroke(
                            viewModel.displayedRouteColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }

                ForEach(viewModel.displayedItineraryStops) { itineraryStop in
                    Annotation(
                        viewModel.areStopTitlesVisible ? itineraryStop.stop.name : "",
                        coordinate: itineraryStop.stop.coordinate,
                        anchor: .center
                    ) {
                        ItineraryStopDotView(
                            stop: itineraryStop.stop,
                            color: viewModel.displayedRouteColor
                        )
                    }
                    .annotationTitles(viewModel.areStopTitlesVisible ? .visible : .hidden)
                }

                ForEach(viewModel.displayedStopEntrances) { entrance in
                    Annotation(entrance.name, coordinate: entrance.coordinate, anchor: .center) {
                        EntranceMarkerView(entrance: entrance)
                    }
                    .annotationTitles(.visible)
                }

                ForEach(viewModel.displayedDots) { dot in
                    Annotation("", coordinate: dot.coordinate, anchor: .center) {
                        DotMarkerView(dot: dot)
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(viewModel.displayedStops) { stop in
                    Annotation(
                        viewModel.areStopTitlesVisible ? stop.name : "",
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

                ForEach(viewModel.displayedVehicles) { vehicle in
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
            .mapStyle(viewModel.selectedMapMode.mapStyle)
            .mapScope(mapScope)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                if newWidth > 0 {
                    viewModel.viewportWidthPoints = Double(newWidth)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.handleCameraChange(to: context)
            }
            .mapControls {
                // Native compass lives in TopChromeView alongside the city picker; no scale/pitch extras.
            }

            TopChromeView(viewModel: viewModel, mapScope: mapScope)
        }
        .overlay(alignment: .bottomTrailing) {
            MapControlsComboView(
                viewModel: viewModel,
                locationManager: locationManager
            )
            .padding(.trailing, DesignTokens.horizontalPadding)
            .padding(.bottom, DesignTokens.bottomPadding)
        }
        .onAppear {
            viewModel.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                viewModel.saveCameraPosition()
                viewModel.pauseForBackground()
                locationManager.stopUpdatingLocation()
            } else if newPhase == .active {
                viewModel.resumeFromBackground()
            }
        }
        .sheet(isPresented: isDetailSheetPresented) {
            detailSheetContent
        }
    }

    @ViewBuilder
    private var detailSheetContent: some View {
        if let tripDetail = viewModel.activeTripDetail {
            VehicleDetailSheet(
                detail: tripDetail,
                timeZone: viewModel.timeZone(for: tripDetail.city),
                canNavigateBack: viewModel.canNavigateBackToStop,
                isFollowingVehicle: viewModel.isFollowingVehicle,
                onBack: { viewModel.navigateBackToStop() },
                onToggleFollow: { viewModel.toggleFollowVehicle() },
                onDismiss: { viewModel.selection = nil }
            )
            .presentationDetents([.height(DesignTokens.vehicleSheetSmallDetentHeight), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else if let stopDetail = viewModel.activeStopDetail {
            StopDetailSheet(
                stop: stopDetail.stop,
                departures: stopDetail.departures,
                isLoadingDepartures: stopDetail.isLoadingDepartures,
                errorMessage: stopDetail.errorMessage,
                timeZone: viewModel.timeZone(for: stopDetail.stop.city),
                onSelectDeparture: { departure in
                    viewModel.openDeparture(departure)
                },
                onDismiss: { viewModel.selection = nil }
            )
            .presentationDetents([.height(DesignTokens.sheetSmallDetentHeight), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}

private struct TopChromeView: View {
    @Bindable var viewModel: MapViewModel
    let mapScope: Namespace.ID

    var body: some View {
        VStack(spacing: DesignTokens.controlSpacing) {
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

    private var cityPickerLabelText: String {
        viewModel.selectedCity?.name ?? String(localized: "cityPicker.title")
    }

    private var cityPickerButton: some View {
        Button {
            viewModel.isShowingCityPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(cityPickerLabelText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.glass)
        .disabled(viewModel.pickerCities.isEmpty)
        .accessibilityLabel(Text("map.control.cityPicker"))
        .accessibilityValue(Text(cityPickerLabelText))
        .sheet(isPresented: $viewModel.isShowingCityPicker) {
            CityPickerSheet(
                cities: viewModel.pickerCities,
                selectedCity: viewModel.selectedCity
            ) { city in
                viewModel.selectCity(city)
            }
        }
    }

    private var trailingControls: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.controlSpacing) {
            MapCompass(scope: mapScope)
                .mapControlVisibility(.automatic)

            if viewModel.isPitched3D {
                Button {
                    viewModel.resetPitchTo2D()
                } label: {
                    Text("map.control.2d")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: DesignTokens.compactControlSize, height: DesignTokens.compactControlSize)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(minWidth: DesignTokens.controlSize, minHeight: DesignTokens.controlSize)
                .contentShape(Circle())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text("map.control.2d.accessibility"))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPitched3D)
    }

    @ViewBuilder
    private var statusCapsule: some View {
        if viewModel.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(LocalizedStringKey(loadingMessage))
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect()
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let error = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)

                if viewModel.isRetryableError {
                    Button {
                        viewModel.retry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.bold))
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("map.error.retry"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect()
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func regionSuggestionCapsule(for city: City) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.switchToSuggestedCity()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text(
                        String(
                            format: String(localized: "map.suggestion.switchCity"),
                            city.name
                        )
                    )
                    .font(.footnote.weight(.semibold))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                viewModel.dismissSuggestedCity()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("map.suggestion.dismiss"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .glassEffect()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var loadingMessage: String {
        if viewModel.stops.isEmpty && viewModel.vehicles.isEmpty && viewModel.dots.isEmpty {
            return "map.loading.initial"
        }
        return "map.loading.refresh"
    }
}

private struct StopAnnotationContent: View {
    let stop: Stop
    let viewModel: MapViewModel
    let onSelect: () -> Void

    var body: some View {
        let heading: Double = stop.bearing != nil ? viewModel.currentHeading : 0
        StopMarkerView(
            stop: stop,
            heading: heading,
            isSelected: viewModel.selectedStopID == stop.id
        )
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
        let heading: Double = vehicle.bearing != nil ? viewModel.currentHeading : 0
        VehicleMarkerView(
            vehicle: vehicle,
            heading: heading,
            isSelected: viewModel.selectedVehicleID == vehicle.id
        )
        .onTapGesture {
            onSelect()
        }
    }
}

private struct ItineraryStopDotView: View {
    let stop: Stop
    let color: Color

    var body: some View {
        Circle()
            .fill(Color(.systemBackground))
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2.5)
            )
            .frame(width: MapConstants.itineraryStopMarkerSize, height: MapConstants.itineraryStopMarkerSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(String(format: String(localized: "map.itineraryStop.accessibility"), stop.name))
            )
    }
}

private struct EntranceMarkerView: View {
    let entrance: StopEntrance

    var body: some View {
        Image(systemName: "door.left.hand.open")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.secondary)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(String(format: String(localized: "map.entrance.accessibility"), entrance.name))
            )
    }
}
