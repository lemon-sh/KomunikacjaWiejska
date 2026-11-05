import MapKit
import SwiftUI

public struct TransitMapView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationManager = LocationManager.shared
    @Namespace private var mapScope

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            Map(
                position: $viewModel.cameraPosition,
                selection: $viewModel.selectedStop,
                scope: mapScope
            ) {
                UserAnnotation()

                ForEach(viewModel.stops) { stop in
                    Annotation(stop.displayName, coordinate: stop.coordinate, anchor: .center) {
                        StopMarkerView(
                            stop: stop,
                            isSelected: viewModel.selectedStop?.id == stop.id
                        )
                    }
                    .tag(stop)
                }
            }
            .mapStyle(viewModel.selectedMapMode.mapStyle)
            .onMapCameraChange(frequency: .continuous) { context in
                viewModel.handleCameraChange(to: context)
            }
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()

            // Floating Top Header Controls
            ZStack(alignment: .top) {
                // Top Center: Status Capsule (Zoom Hint, Loading Indicator, or Error)
                VStack(spacing: 0) {
                    Color.clear.frame(height: 52)
                    if viewModel.isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Wczytywanie przystanków...")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    } else if viewModel.isZoomedOutForStops {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.caption)
                            Text("Przybliż mapę, aby zobaczyć przystanki")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    } else if let error = viewModel.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                }

                // Top Controls: City Switcher (leading) & Right Cluster (Reload, Compass, 2D)
                HStack(alignment: .top) {
                    // City Switcher Button with .glass style
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

                    Spacer()

                    // Top Right Cluster: Reload Button, UIKit Compass, and 2D Button
                    VStack(alignment: .trailing, spacing: 10) {
                        // Reload Button with .glass style
                        Button {
                            viewModel.refreshStops()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)

                        // UIKit Compass placed directly below the refresh button
                        MapCompass(scope: mapScope)

                        // 2D Button: appears when map pitch is tilted in 3D
                        if viewModel.isPitched3D {
                            Button {
                                viewModel.resetPitchTo2D()
                            } label: {
                                Text("2D")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.primary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isPitched3D)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        // Bottom Right: Apple Maps Map Style + Location Combo Capsule
        .overlay(alignment: .bottomTrailing) {
            MapControlsComboView(
                viewModel: viewModel,
                locationManager: locationManager
            )
            .padding(.trailing, 16)
            .padding(.bottom, 36)
        }
        .mapScope(mapScope)
        .onAppear {
            locationManager.requestWhenInUseAuthorization()
        }
        .sheet(item: $viewModel.selectedStop) { stop in
            StopDetailSheet(stop: stop) {
                viewModel.selectedStop = nil
            }
            .presentationDetents([.height(240), .medium])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .height(240)))
        }
        .sheet(isPresented: $viewModel.isShowingCityPicker) {
            CityPickerSheet(selectedCity: $viewModel.selectedCity)
        }
    }
}
