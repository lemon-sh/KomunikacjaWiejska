import CoreLocation
import Foundation
import MapKit
import SwiftUI
import Testing
@testable import KomunikacjaWiejska

/// Unit tests for `MapViewModel` SSE lifecycle, dots zoom mode, selection isolation, and navigation.

@Suite("MapViewModel Tests")
@MainActor
struct MapViewModelTests {
    private func makeViewModel(
        provider: StubStopsProvider = StubStopsProvider(),
        persistence: CameraPersistenceStore = InMemoryCameraPersistenceStore()
    ) -> MapViewModel {
        MapViewModel(
            transitDataProvider: provider,
            persistence: persistence,
            debounceDuration: .milliseconds(10)
        )
    }

    @Test("Default state, map mode toggling, and persistence restoration from fetched catalog")
    func testInitialStateAndPersistenceRestoration() async throws {
        let store = InMemoryCameraPersistenceStore()
        store.saveLastSelectedCityID("krakow")
        store.saveCamera(
            latitude: 50.06865,
            longitude: 19.94781,
            distance: 2_500
        )

        let viewModel = makeViewModel(persistence: store)
        #expect(viewModel.citiesCatalog.isEmpty)
        #expect(viewModel.selectedCity == nil)
        #expect(viewModel.selectedCityID == "krakow")
        #expect(viewModel.currentDistance == 2_500)
        #expect(viewModel.selectedMapMode == .explore)
        #expect(viewModel.isTrackingUser == false)

        viewModel.toggleMapMode()
        #expect(viewModel.selectedMapMode == .satellite)
        viewModel.toggleMapMode()
        #expect(viewModel.selectedMapMode == .explore)

        viewModel.start()
        try await waitUntil { viewModel.selectedCity?.id == "krakow" }
        #expect(abs(viewModel.cameraState.center.latitude - 50.06865) < 1e-4)
        #expect(viewModel.currentDistance == 2_500)
    }

    @Test("start loads dynamic /api6 cities and streams mapFeatures initial + message")
    func testStartLoadsDynamicCitiesAndStreamsFeatures() async throws {
        let helsinki = City(
            id: "helsinki",
            name: "Helsinki",
            latitude: 60.1708,
            longitude: 24.9415,
            timezoneIdentifier: "Europe/Helsinki"
        )
        let stop = StubStopsProvider.sampleStop(id: "h1", city: "warsaw", name: "Centrum")
        let vehicle = StubStopsProvider.sampleVehicle(id: "v1", city: "warsaw")

        let provider = StubStopsProvider(
            cities: [StubStopsProvider.sampleWarsaw, StubStopsProvider.sampleKrakow, helsinki, StubStopsProvider.samplePKP]
        ) { _, _, _ in
            [
                .initial(MapFeaturesInitial(stops: [stop])),
                .message(MapFeaturesUpdate(positions: [vehicle], dots: []))
            ]
        }

        let viewModel = makeViewModel(provider: provider)
        viewModel.start()

        try await waitUntil {
            viewModel.citiesCatalog.contains(where: { $0.id == "helsinki" })
                && viewModel.stops.count == 1
                && viewModel.vehicles.count == 1
        }

        #expect(viewModel.selectedCity?.id == "warsaw")
        #expect(viewModel.pickerCities.contains(where: { $0.id == "helsinki" }))
        #expect(!viewModel.pickerCities.contains(where: { $0.id == "pkp" }))
        #expect(viewModel.displayedStops == [stop])
        #expect(viewModel.displayedVehicles == [vehicle])
        #expect(viewModel.displayedDots.isEmpty)
        #expect(viewModel.loadingPhase == .idle)
    }

    @Test("Zoomed-out mapFeatures populates dots and clears positions")
    func testZoomedOutDotsRendering() async throws {
        let dot = StubStopsProvider.sampleDot(colorHex: "#296d00")
        let provider = StubStopsProvider { _, _, _ in
            [
                .initial(MapFeaturesInitial(stops: [])),
                .message(MapFeaturesUpdate(positions: [], dots: [dot]))
            ]
        }

        let viewModel = makeViewModel(provider: provider)
        viewModel.start()

        try await waitUntil { viewModel.dots == [dot] }
        #expect(viewModel.displayedStops.isEmpty)
        #expect(viewModel.displayedVehicles.isEmpty)
        #expect(viewModel.displayedDots == [dot])
    }

    @Test("City switch cancels prior state and opens stream for new city")
    func testCitySwitchClearsPreviousDataAndRestartsStream() async throws {
        let krakowStop = StubStopsProvider.sampleStop(id: "k1", city: "krakow", name: "Teatr Bagatela")
        let warsawStop = StubStopsProvider.sampleStop(id: "w1", city: "warsaw", name: "Politechnika")

        let provider = StubStopsProvider { city, _, _ in
            if city == "krakow" {
                return [.initial(MapFeaturesInitial(stops: [krakowStop]))]
            }
            return [.initial(MapFeaturesInitial(stops: [warsawStop]))]
        }

        let store = InMemoryCameraPersistenceStore()
        let viewModel = makeViewModel(provider: provider, persistence: store)
        viewModel.start()
        try await waitUntil { viewModel.stops == [warsawStop] }

        viewModel.selectCity(StubStopsProvider.sampleKrakow)
        try await waitUntil { viewModel.stops == [krakowStop] }
        #expect(store.loadLastSelectedCityID() == "krakow")
        #expect(viewModel.selectedCity?.id == "krakow")
        #expect(viewModel.vehicles.isEmpty)
    }

    @Test("Stop selection uses stop.city (cross-city safe), hydrates 10-tuple Stop, and isolates map layers")
    func testStopSelectionIsolationAndCrossCityStream() async throws {
        let mapStop7Tuple = StubStopsProvider.sampleStop(
            id: "mld-stop-1",
            city: "mld",
            name: "Kraków MDA",
            code: "01",
            lon: 19.95,
            lat: 50.06
        )
        let otherStop = StubStopsProvider.sampleStop(id: "other-1", city: "krakow", name: "Kleparz")
        let departureVehicle = StubStopsProvider.sampleVehicle(id: "3:MLD_151", city: "mld", routeName: "A1")
        let hydratedStop = StubStopsProvider.sampleStop(
            id: "mld-stop-1",
            city: "mld",
            name: "Kraków MDA",
            code: "01",
            lon: 19.95,
            lat: 50.06,
            direction: "Myślenice",
            routes: [StubStopsProvider.sampleRoute(id: "A1", city: "mld", name: "A1")],
            entrances: [StopEntrance(id: "mld-stop-1-entrance-0", name: "Wejście", latitude: 50.061, longitude: 19.951)],
            hasFullMetadata: true
        )
        let departure = StopDeparture(
            trip: TripInfo(
                id: "trip-a1",
                city: "mld",
                route: StubStopsProvider.sampleRoute(id: "A1", city: "mld", name: "A1"),
                headsign: "Myślenice D.A."
            ),
            vehicle: departureVehicle,
            departure: StopTimeUpdate(scheduledMs: 1_794_433_020_000, delayMs: 60_000, status: .onTrip)
        )

        let provider = StubStopsProvider(
            mapStreamHandler: { _, _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(MapFeaturesInitial(stops: [mapStop7Tuple, otherStop])))
                    c.yield(.message(MapFeaturesUpdate(positions: [], dots: [StubStopsProvider.sampleDot()])))
                    c.finish()
                }
            },
            stopStreamHandler: { _, _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(hydratedStop))
                    c.yield(.message([departure]))
                    c.finish()
                }
            }
        )

        let viewModel = makeViewModel(provider: provider)
        viewModel.selectCity(StubStopsProvider.sampleKrakow, repositionCamera: false)
        viewModel.start()
        try await waitUntil { viewModel.stops.count == 2 && !viewModel.dots.isEmpty }

        viewModel.selection = .stop("mld-stop-1")

        try await waitUntil {
            viewModel.activeStopDetail?.stop.hasFullMetadata == true
                && viewModel.activeStopDetail?.departures.count == 1
        }

        // Opened stream under stop's own city (`mld`), not viewport city (`krakow`).
        #expect(provider.requestedStopRequests.last?.city == "mld")
        #expect(provider.requestedStopRequests.last?.stopId == "mld-stop-1")
        // Isolated layers: only selected stop, its entrances, and departure live vehicle.
        #expect(viewModel.displayedStops == [hydratedStop])
        #expect(viewModel.displayedVehicles == [departureVehicle])
        #expect(viewModel.displayedStopEntrances.count == 1)
        #expect(viewModel.displayedDots.isEmpty)
    }

    @Test("Tapping live or scheduled departure transitions to Trip sheet with polyline and supports Back to Stop")
    func testDepartureToTripNavigationAndBackStack() async throws {
        let stop = StubStopsProvider.sampleStop(id: "s1", city: "krakow", name: "Teatr Słowackiego")
        let liveVehicle = StubStopsProvider.sampleVehicle(id: "3:DE631", city: "krakow", routeName: "124")
        let liveDep = StopDeparture(
            trip: TripInfo(id: "t-live", city: "krakow", route: liveVehicle.route, headsign: "Tauron Arena"),
            vehicle: liveVehicle,
            departure: StopTimeUpdate(scheduledMs: 1_794_433_020_000, delayMs: 0, status: .onTrip)
        )
        let schedDep = StopDeparture(
            trip: TripInfo(id: "t-sched", city: "krakow", route: liveVehicle.route, headsign: "Os. Podwawelskie"),
            vehicle: nil,
            departure: StopTimeUpdate(scheduledMs: 1_794_457_200_000, delayMs: 0, status: .scheduled)
        )

        let itinerary = Itinerary(
            stops: [ItineraryStop(stop: stop, alight: .regular)],
            encodedPolyline: "o_pp~Ai}v_e@?g@"
        )
        let tripInitial = TripInitial(trip: liveDep.trip, itinerary: itinerary)
        let tripUpdate = TripUpdate(
            position: liveVehicle,
            stops: [
                TripStopUpdate(
                    arrival: StopTimeUpdate(scheduledMs: 1_794_433_020_000, delayMs: 60_000, status: .onTrip),
                    departure: StopTimeUpdate(scheduledMs: 1_794_433_020_000, delayMs: 60_000, status: .onTrip)
                )
            ],
            sequence: 0,
            alerts: []
        )

        let provider = StubStopsProvider(
            mapStreamHandler: { _, _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(MapFeaturesInitial(stops: [stop])))
                    c.finish()
                }
            },
            stopStreamHandler: { _, _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(stop))
                    c.yield(.message([liveDep, schedDep]))
                    c.finish()
                }
            },
            vehicleStreamHandler: { _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(tripInitial))
                    c.yield(.message(tripUpdate))
                    c.finish()
                }
            },
            tripStreamHandler: { _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(TripInitial(trip: schedDep.trip, itinerary: itinerary)))
                    c.finish()
                }
            },
            vehicleMetadataHandler: { _, id in
                VehicleMetadata(id: id, model: "Solaris Urbino 12", prodYear: 2023, carrier: "MPK Kraków")
            }
        )

        let viewModel = makeViewModel(provider: provider)
        viewModel.selectCity(StubStopsProvider.sampleKrakow, repositionCamera: false)
        viewModel.start()
        try await waitUntil { !viewModel.stops.isEmpty }

        viewModel.selection = .stop("s1")
        try await waitUntil { viewModel.activeStopDetail?.departures.count == 2 }

        // Open live departure
        viewModel.openDeparture(liveDep)
        try await waitUntil {
            viewModel.activeTripDetail?.itinerary != nil
                && viewModel.activeTripDetail?.vehicleMetadata?.model == "Solaris Urbino 12"
        }

        #expect(viewModel.canNavigateBackToStop == true)
        #expect(viewModel.displayedStops.isEmpty)
        #expect(viewModel.displayedItineraryStops.count == 1)
        #expect(viewModel.displayedRouteCoordinates.count == 2)
        #expect(viewModel.displayedVehicles == [liveVehicle])

        // Follow vehicle mode centers cleanly and resets on manual gesture
        viewModel.toggleFollowVehicle()
        #expect(viewModel.isFollowingVehicle == true)
        viewModel.setCameraPositionFromGesture(.automatic)
        #expect(viewModel.isFollowingVehicle == false)

        // Back button returns to StopDetailSheet
        viewModel.navigateBackToStop()
        try await waitUntil { viewModel.activeStopDetail?.stop.id == "s1" }
        #expect(viewModel.canNavigateBackToStop == false)
        #expect(viewModel.activeTripDetail == nil)

        // Scheduled departure without live vehicle opens trips/{id}/stream
        viewModel.openDeparture(schedDep)
        try await waitUntil { viewModel.activeTripDetail?.tripId == "t-sched" }
        #expect(provider.requestedTripRequests.last?.tripId == "t-sched")
        #expect(viewModel.displayedVehicles.isEmpty)
    }

    @Test("Region suggestion prioritizes server suggestedCity, excludes virtual networks, and handles dismissal")
    func testRegionSuggestionServerAndFallback() async throws {
        let provider = StubStopsProvider { _, _, _ in
            [
                .initial(MapFeaturesInitial(stops: [], suggestedCity: "krakow"))
            ]
        }

        let viewModel = makeViewModel(provider: provider)
        viewModel.start()
        try await waitUntil { viewModel.suggestedCity?.id == "krakow" }

        viewModel.dismissSuggestedCity()
        #expect(viewModel.suggestedCity == nil)
        #expect(viewModel.dismissedCityID == "krakow")

        // Moving > 5km away resets dismissal and local lookup finds Poznań in catalog.
        let poznan = StubStopsProvider.samplePoznan
        viewModel.cameraState = MapViewModel.CameraState(
            region: MKCoordinateRegion(
                center: poznan.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ),
            distance: 3_000,
            heading: 0,
            pitch: 0,
            center: poznan.coordinate
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.dismissedCityID == nil)
        #expect(viewModel.suggestedCity?.id == "poznan")

        // Nearest suggestion excludes virtual networks even when centered directly on PKP.
        let virtualOnly = MapViewModel.nearestSuggestedCity(
            for: CLLocationCoordinate2D(latitude: 52.0, longitude: 19.5),
            currentCity: StubStopsProvider.samplePKP,
            dismissedCityID: nil,
            allCities: StubStopsProvider.sampleCities
        )
        #expect(virtualOnly?.isVirtual != true)
    }

    @Test("Stream errors populate retryable error state without crashing")
    func testStreamErrorState() async throws {
        let provider = StubStopsProvider { _, _, _ in
            throw ZbiorkomAPIError.httpError(statusCode: 503)
        }

        let viewModel = makeViewModel(provider: provider)
        viewModel.start()
        try await waitUntil { viewModel.errorMessage != nil }
        #expect(viewModel.isRetryableError == true)
    }

    @Test("Failed /api6 city fetch shows retryable error without fallback catalog and recovers on retry")
    func testCitiesFetchFailureAndRetryRecovery() async throws {
        actor FetchState {
            var shouldFail = true
            func nextCities() throws -> [City] {
                if shouldFail {
                    throw ZbiorkomAPIError.httpError(statusCode: 503)
                }
                return StubStopsProvider.sampleCities
            }
            func allowSuccess() {
                shouldFail = false
            }
        }

        let state = FetchState()
        let stop = StubStopsProvider.sampleStop(id: "w1", city: "warsaw", name: "Centrum")
        let provider = StubStopsProvider(
            citiesHandler: { try await state.nextCities() },
            mapStreamHandler: { _, _, _ in
                AsyncThrowingStream { c in
                    c.yield(.initial(MapFeaturesInitial(stops: [stop])))
                    c.finish()
                }
            }
        )

        let viewModel = makeViewModel(provider: provider)
        viewModel.start()

        try await waitUntil { viewModel.errorMessage != nil }
        #expect(viewModel.isRetryableError == true)
        #expect(viewModel.citiesCatalog.isEmpty)
        #expect(viewModel.selectedCity == nil)
        #expect(provider.requestedMapRequests.isEmpty)

        await state.allowSuccess()
        viewModel.retry()

        try await waitUntil { viewModel.selectedCity?.id == "warsaw" && viewModel.stops == [stop] }
        #expect(viewModel.errorMessage == nil)
        #expect(provider.requestedMapRequests.last?.city == "warsaw")
    }
}
