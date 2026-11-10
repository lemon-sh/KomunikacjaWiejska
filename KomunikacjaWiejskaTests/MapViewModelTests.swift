import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import MapKit
import SwiftUI
import Testing

@Suite("MapViewModel Tests")
@MainActor
struct MapViewModelTests {
    @Test("MapViewModel map mode and user location controls")
    func testMapViewModelControls() {
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)
        #expect(viewModel.selectedMapMode == .explore)
        #expect(viewModel.isShowingMapModes == false)
        #expect(viewModel.isTrackingUser == false)

        viewModel.selectedMapMode = .satellite
        #expect(viewModel.selectedMapMode == .satellite)
        viewModel.toggleMapMode()
        #expect(viewModel.selectedMapMode == .explore)
        viewModel.toggleMapMode()
        #expect(viewModel.selectedMapMode == .satellite)

        let targetCoord = CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
        viewModel.centerOnUserLocation(coordinate: targetCoord)
        #expect(viewModel.isTrackingUser == true)
        #expect(viewModel.currentCenter.latitude == targetCoord.latitude)
        #expect(viewModel.currentCenter.longitude == targetCoord.longitude)
    }

    @Test("MapViewModel construction performs no network request")
    func testConstructionDoesNoIO() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        _ = MapViewModel(apiClient: provider, initialCity: .warsaw)

        #expect(provider.callCount == 0)
    }

    @Test("loadStopsForSelectedCity fetches exactly once and settles loading state")
    func testLoadFetchesOnce() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)

        // Viewport strategy passes the visible bounding box to the API
        #expect(provider.requestedBBoxes.first != nil)
        #expect(provider.requestedBBoxes.first??.queryValue.contains(",") == true)
    }

    @Test("Loading phase distinguishes initial load, same-city viewport load, and completion")
    func testLoadingPhases() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()], holdsRequests: true)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntil { !provider.requestedCities.isEmpty }
        #expect(viewModel.loadingPhase == .initial)

        provider.openGate()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.loadingPhase == nil)

        // A different viewport in the same city is a plain reload, not a city switch
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.20),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        provider.holdRequests()
        viewModel.loadStopsForSelectedCity()
        try await waitUntil { provider.requestedCities.count >= 2 }
        #expect(viewModel.loadingPhase == .refresh)

        provider.openGate()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.loadingPhase == nil)
    }

    @Test("Typed load state and city switching without string parsing")
    func testTypedLoadStateAcrossCitySwitch() async throws {
        let provider = StubStopsProvider(holdsRequests: true)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        #expect(viewModel.isLoading)
        #expect(viewModel.loadingPhase == .initial)

        // Switch to Krakow while Warsaw is loading
        viewModel.selectCity(.krakow, repositionCamera: false)
        #expect(viewModel.isLoading)
        #expect(viewModel.loadingPhase == .citySwitch)

        provider.openGate()
        try await waitUntilLoaded(viewModel)
        #expect(!viewModel.isLoading)
        #expect(viewModel.loadingPhase == nil)
    }

    @Test("Visible stops are rendered in deterministic ID order without thinning")
    func testVisibleStopsRenderedWithoutThinning() async throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2, longitude: 21.0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let stops = (0..<50).map { index in
            StopFixtures.sample(
                id: String(format: "stop-%04d", 49 - index),
                longitude: 21.0 + Double(index) * 0.0005,
                latitude: 52.2 + Double(index) * 0.0005
            )
        }

        let provider = StubStopsProvider(stops: stops)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.cameraState = MapViewModel.CameraState(
            region: region,
            distance: 2_000,
            center: region.center
        )

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.stops.count == 50)
        #expect(viewModel.stops.map(\.id) == stops.map(\.id).sorted())
    }

    @Test("Repeated loads and camera changes use the cache without refetching")
    func testStopsKeptInMemory() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)

        let dummyRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.0, longitude: 21.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        viewModel.visibleRegion = dummyRegion
        #expect(viewModel.stops.count == 1)

        viewModel.visibleRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: City.warsaw.defaultLatitudeDelta,
                longitudeDelta: City.warsaw.defaultLongitudeDelta
            )
        )
        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)
    }

    @Test("A new viewport applies updated stop details with unchanged IDs")
    func testViewportLoadAppliesUpdatedStopContent() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample(bearing: 90)])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.stops.first?.bearing == 90)

        provider.setStops([StopFixtures.sample(bearing: 180, longitude: 21.20, latitude: 52.23)])
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.20),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.stops.first?.bearing == 180)
    }

    @Test("Stop selection updates selectedStop and cachedStop lookup")
    func testStopSelection() async throws {
        let stopA = StopFixtures.sample(id: "stop-a", name: "Stop Alpha")
        let stopB = StopFixtures.sample(id: "stop-b", name: "Stop Beta")
        let provider = StubStopsProvider(stops: [stopA, stopB])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.selectedStopID == nil)
        #expect(viewModel.selectedStop == nil)
        #expect(viewModel.cachedStop(for: "stop-a")?.name == "Stop Alpha")
        #expect(viewModel.cachedStop(for: "stop-b")?.name == "Stop Beta")
        #expect(viewModel.cachedStop(for: "non-existent") == nil)

        viewModel.selectedStopID = "stop-a"
        #expect(viewModel.selectedStop?.id == "stop-a")
        #expect(viewModel.selectedStop?.name == "Stop Alpha")

        viewModel.selectedStopID = "stop-b"
        #expect(viewModel.selectedStop?.id == "stop-b")
        #expect(viewModel.selectedStop?.name == "Stop Beta")

        viewModel.selectedStopID = nil
        #expect(viewModel.selectedStop == nil)
    }

    @Test("Selected stop is preserved in rendered stops")
    func testSelectedStopPreserved() async throws {
        let count = 50
        var allStops: [Stop] = []
        for index in 0..<count {
            allStops.append(
                StopFixtures.sample(
                    id: String(format: "stop-%03d", index),
                    longitude: 21.0 + Double(index) * 0.0001,
                    latitude: 52.2 + Double(index) * 0.0001
                )
            )
        }

        let targetID = "stop-025"
        let provider = StubStopsProvider(stops: allStops)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000
        viewModel.selectedStopID = targetID

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.stops.contains(where: { $0.id == targetID }))
    }

    @Test("Vehicles spatial grid thinning caps rendered count to maxRenderedVehicles and preserves selected vehicle")
    func testVehicleSpatialGridThinning() async throws {
        let count = 200
        var allVehicles: [VehiclePosition] = []
        for index in 0..<count {
            allVehicles.append(
                VehicleFixtures.sample(
                    id: String(format: "%04d", index),
                    longitude: 21.0 + Double(index) * 0.0002,
                    latitude: 52.2 + Double(index) * 0.0002
                )
            )
        }

        let selectedID = "default:3:0150"
        let provider = StubStopsProvider(vehicles: allVehicles)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 4_000
        viewModel.selectedVehicleID = selectedID

        await viewModel.fetchVehiclesForCurrentViewport()

        #expect(viewModel.vehicles.count <= MapViewModel.maxRenderedVehicles)
        #expect(viewModel.vehicles.contains(where: { $0.id == selectedID }))
    }

    @Test("Vehicle distance thresholds control visibility and compact display mode")
    func testVehicleDistanceThresholds() {
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)

        viewModel.currentDistance = 1_500
        #expect(viewModel.isVehiclesVisible == true)
        #expect(viewModel.isVehicleCompactDisplayMode == false)

        viewModel.currentDistance = 5_000
        #expect(viewModel.isVehiclesVisible == true)
        #expect(viewModel.isVehicleCompactDisplayMode == true)

        viewModel.currentDistance = 12_000
        #expect(viewModel.isVehiclesVisible == false)
    }

    @Test("Vehicle selection is mutually exclusive with stop selection and enables tracking")
    func testVehicleSelectionAndTracking() async throws {
        let vehicle = VehicleFixtures.sample(id: "500", longitude: 21.02, latitude: 52.24)
        let stop = StopFixtures.sample(id: "stop-1")
        let provider = StubStopsProvider(stops: [stop], vehicles: [vehicle])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        await viewModel.fetchVehiclesForCurrentViewport()

        // Select stop first
        viewModel.selectedStopID = stop.id
        #expect(viewModel.selectedStopID == stop.id)
        #expect(viewModel.selectedVehicleID == nil)

        // Select vehicle: mutual exclusivity
        viewModel.selection = .vehicle(vehicle.id)
        #expect(viewModel.selectedVehicleID == vehicle.id)
        #expect(viewModel.selectedStopID == nil)
        #expect(viewModel.isTrackingVehicle == true)

        // Manual gesture cancels tracking
        viewModel.setCameraPositionFromGesture(.region(MKCoordinateRegion()))
        #expect(viewModel.isTrackingVehicle == false)
    }

    @Test("Vehicle network failure marks error as non-retryable")
    func testVehicleNetworkErrorNonRetryable() async throws {
        struct VehicleNetworkError: LocalizedError {
            var errorDescription: String? { "Vehicle service unavailable" }
        }
        let provider = StubStopsProvider(vehicleError: VehicleNetworkError())
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        await viewModel.fetchVehiclesForCurrentViewport()

        #expect(viewModel.errorMessage == "Vehicle service unavailable")
        #expect(viewModel.isRetryableError == false)
    }

    @Test("Selecting a stop does not recompute rendered stops array instance if stop is already present")
    func testSelectionDoesNotRecomputeStops() async throws {
        let stopA = StopFixtures.sample(id: "stop-a", name: "A")
        let stopB = StopFixtures.sample(id: "stop-b", name: "B")
        let provider = StubStopsProvider(stops: [stopA, stopB])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        let originalStops = viewModel.stops
        #expect(originalStops.count == 2)

        viewModel.selectedStopID = "stop-a"
        #expect(viewModel.stops == originalStops)

        viewModel.selectedStopID = "stop-b"
        #expect(viewModel.stops == originalStops)

        viewModel.selectedStopID = nil
        #expect(viewModel.stops == originalStops)
    }

    @Test("Rotating and pitching at a fixed center issues zero network requests")
    func testRotationAndPitchIssuesZeroRequests() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        let initialCallCount = provider.callCount

        let currentCenter = viewModel.currentCenter
        let currentDistance = viewModel.currentDistance
        let currentRegion = viewModel.visibleRegion!

        let rotatedState = MapViewModel.CameraState(
            region: currentRegion,
            heading: 45.0,
            pitch: 30.0,
            distance: currentDistance,
            center: currentCenter
        )
        viewModel.applyCameraState(rotatedState)
        try await Task.sleep(for: .milliseconds(450))

        #expect(provider.callCount == initialCallCount)
    }

    @Test("Errors do not survive a city round-trip")
    func testCityErrorDoesNotSurviveRoundTrip() async throws {
        struct TestError: LocalizedError {
            var errorDescription: String? { "Failed to load" }
        }
        let provider = StubStopsProvider(
            resultsByCity: [
                "warsaw": .failure(TestError()),
                "krakow": .success([StopFixtures.sample(city: "krakow")])
            ]
        )
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.errorMessage == "Failed to load")

        viewModel.selectCity(.krakow)
        viewModel.currentDistance = 2_000
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.errorMessage == nil)

        provider.setStops([StopFixtures.sample(city: "warsaw")])
        viewModel.selectCity(.warsaw)
        viewModel.currentDistance = 2_000
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("A viewport that leaves fetched tile coverage requests new tiles")
    func testViewportOutsideCoverageFetches() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let startingCity = City(
            id: "warsaw",
            name: "Warszawa",
            coordinate: CLLocationCoordinate2D(latitude: 52.2300, longitude: 21.0100),
            defaultLatitudeDelta: 0.08,
            defaultLongitudeDelta: 0.08
        )
        let viewModel = MapViewModel(apiClient: provider, initialCity: startingCity)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 1)

        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2300, longitude: 21.2000),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(provider.callCount == 2)
    }

    @Test("A viewport inside fetched tile coverage reuses the cache")
    func testViewportInsideCoverageDoesNotFetch() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000
        let initialRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: City.warsaw.defaultLatitudeDelta,
                longitudeDelta: City.warsaw.defaultLongitudeDelta
            )
        )

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 1)

        let coverage = try #require(
            MapTileGrid.boundingBox(covering: MapTileGrid.visibleTiles(in: initialRegion))
        )
        let coveredRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (coverage.minLat + coverage.maxLat) / 2,
                longitude: (coverage.minLon + coverage.maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )

        viewModel.visibleRegion = coveredRegion
        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)
    }

    @Test("Zooming in within covered Zoom 12 tiles reuses the cache")
    func testZoomingInUsesTileCoverage() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 1)

        viewModel.visibleRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)
    }

    @Test("Zooming out within stop visibility threshold fetches additional Zoom 12 tiles")
    func testZoomingOutFetchesAdditionalCoverage() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000
        let wideRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        viewModel.visibleRegion = wideRegion
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 2)

        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 2)
    }

    @Test("Stops merge across fetches and rendering is filtered to the viewport")
    func testStopsMergeAndFilterAcrossViewports() async throws {
        let stopA = StopFixtures.sample(
            id: "warsaw-a",
            city: "warsaw",
            longitude: 21.0100,
            latitude: 52.2300
        )
        let stopB = StopFixtures.sample(
            id: "warsaw-b",
            city: "warsaw",
            longitude: 21.5000,
            latitude: 52.5000
        )
        let provider = StubStopsProvider(stops: [stopA])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.stops == [stopA])

        provider.setStops([stopB])
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.5000, longitude: 21.5000),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.stops == [stopB])

        viewModel.visibleRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: City.warsaw.defaultLatitudeDelta,
                longitudeDelta: City.warsaw.defaultLongitudeDelta
            )
        )
        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 2)
        #expect(viewModel.stops == [stopA])
    }

    @Test("An empty successful response still marks tiles as fetched")
    func testEmptyResponseMarksTiles() async throws {
        let provider = StubStopsProvider(stops: [])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.isEmpty)

        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
    }

    @Test("Fetch errors surface a message and mark the city as failed")
    func testFetchErrorSurfacesMessage() async throws {
        struct NetworkFailure: Error {}
        let provider = StubStopsProvider(error: NetworkFailure())
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(provider.callCount == 1)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.stops.isEmpty)
        #expect(viewModel.loadingPhase == nil)

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(provider.callCount == 2)
    }

    @Test("Switching city while a request is in flight shows no stale data")
    func testCitySwitchWhileInFlightDiscardsStaleResponse() async throws {
        let warsawStops = [StopFixtures.sample(id: "a", city: "warsaw")]
        let krakowStops = [StopFixtures.sample(
            id: "b",
            city: "krakow",
            longitude: City.krakow.coordinate.longitude,
            latitude: City.krakow.coordinate.latitude
        )]
        let provider = StubStopsProvider(
            resultsByCity: [
                "warsaw": .success(warsawStops),
                "krakow": .success(krakowStops),
            ],
            holdsRequests: true
        )
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntil { provider.requestedCities.count >= 1 }
        #expect(provider.requestedCities == ["warsaw"])
        #expect(viewModel.isLoading == true)

        viewModel.selectCity(.krakow)
        viewModel.currentDistance = 2_000
        viewModel.loadStopsForSelectedCity()
        try await waitUntil { provider.requestedCities.count >= 2 }
        #expect(viewModel.stops.isEmpty)
        #expect(provider.requestedCities == ["warsaw", "krakow"])
        #expect(viewModel.loadingPhase == .citySwitch)

        provider.openGate()
        try await waitUntilLoaded(viewModel)

        #expect(provider.callCount == 2)
        #expect(viewModel.stops == krakowStops)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Switching cities clears the session cache and refetches on return")
    func testCitySwitchClearsCache() async throws {
        let warsawStops = [StopFixtures.sample(id: "a", city: "warsaw")]
        let krakowStops = [StopFixtures.sample(
            id: "b",
            city: "krakow",
            longitude: City.krakow.coordinate.longitude,
            latitude: City.krakow.coordinate.latitude
        )]
        let provider = StubStopsProvider(
            resultsByCity: [
                "warsaw": .success(warsawStops),
                "krakow": .success(krakowStops),
            ]
        )
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.stops == warsawStops)

        viewModel.selectCity(.krakow)
        #expect(viewModel.stops.isEmpty)
        viewModel.currentDistance = 2_000
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.stops == krakowStops)

        viewModel.selectCity(.warsaw)
        #expect(viewModel.stops.isEmpty)
        viewModel.currentDistance = 2_000
        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)
        #expect(viewModel.stops == warsawStops)
        #expect(provider.callCount == 3)
    }

    @Test("No region suggestion when viewing current city")
    func testNoRegionSuggestionWhenViewingCurrentCity() {
        let warsaw = City.warsaw
        let suggestion = MapViewModel.detectSuggestedCity(
            center: warsaw.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: warsaw
        )
        #expect(suggestion == nil)
    }

    @Test("Suggests region when viewport moves to a different city")
    func testSuggestsRegionWhenViewportMovesToDifferentCity() {
        let warsaw = City.warsaw
        let krakow = City.krakow
        let suggestion = MapViewModel.detectSuggestedCity(
            center: krakow.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: warsaw
        )
        #expect(suggestion?.id == "krakow")
    }

    @Test("No suggestion when zoomed out to nationwide scale")
    func testNoSuggestionWhenZoomedOutNationwide() {
        let warsaw = City.warsaw
        let krakow = City.krakow
        let suggestion = MapViewModel.detectSuggestedCity(
            center: krakow.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5),
            currentCity: warsaw
        )
        #expect(suggestion == nil)
    }

    @Test("Dismissing suggestion suppresses repeated suggestion until moving away")
    func testDismissSuggestion() throws {
        let warsaw = City.warsaw
        let krakow = City.krakow
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: warsaw)

        viewModel.cameraState = MapViewModel.CameraState(
            region: MKCoordinateRegion(
                center: krakow.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ),
            center: krakow.coordinate
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity?.id == "krakow")

        viewModel.dismissSuggestedCity()
        #expect(viewModel.suggestedCity == nil)
        #expect(viewModel.dismissedCityID == "krakow")

        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity == nil)

        let poznan = try #require(City.city(id: "poznan"))
        viewModel.cameraState = MapViewModel.CameraState(
            region: MKCoordinateRegion(
                center: poznan.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ),
            center: poznan.coordinate
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.dismissedCityID == nil)
        #expect(viewModel.suggestedCity?.id == "poznan")
    }

    @Test("Switching to suggested city preserves camera position and loads stops")
    func testSwitchToSuggestedCityPreservesCameraAndLoadsStops() async throws {
        let customKrakowCenter = CLLocationCoordinate2D(latitude: 50.065, longitude: 19.950)
        let customRegion = MKCoordinateRegion(
            center: customKrakowCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        let provider = StubStopsProvider(
            resultsByCity: [
                "krakow": .success([])
            ]
        )
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.cameraState = MapViewModel.CameraState(
            region: customRegion,
            center: customKrakowCenter
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity?.id == "krakow")

        viewModel.switchToSuggestedCity()

        #expect(viewModel.selectedCity.id == "krakow")
        #expect(viewModel.suggestedCity == nil)
        #expect(viewModel.cameraState.center.latitude == customKrakowCenter.latitude)
        #expect(viewModel.cameraState.center.longitude == customKrakowCenter.longitude)
        #expect(viewModel.cameraState.region.span.latitudeDelta == 0.05)

        try await waitUntilLoaded(viewModel)
        #expect(provider.requestedCities.contains("krakow"))
    }

    @Test("Excludes nationwide PKP from region suggestions")
    func testExcludesPKPFromRegionSuggestions() {
        let pkp = City.pkp
        let suggestion = MapViewModel.detectSuggestedCity(
            center: pkp.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: .warsaw
        )
        #expect(suggestion?.id != "pkp")
    }

    @Test("PKP mode suggests local city when zooming into one")
    func testPKPSuggestsLocalCity() {
        let pkp = City.pkp
        let krakow = City.krakow
        let suggestion = MapViewModel.detectSuggestedCity(
            center: krakow.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: pkp
        )
        #expect(suggestion?.id == "krakow")
    }

    @Test("MapViewModel tracks heading changes in camera state")
    func testMapViewModelTracksHeading() {
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)
        #expect(viewModel.currentHeading == 0)

        viewModel.cameraState = MapViewModel.CameraState(
            region: viewModel.cameraState.region,
            heading: 65.5,
            pitch: 0,
            distance: 1000,
            center: viewModel.cameraState.center
        )
        #expect(viewModel.currentHeading == 65.5)

        viewModel.currentHeading = 120.0
        #expect(viewModel.cameraState.heading == 120.0)
    }

    @Test("Stop visibility threshold hides stops and suppresses fetching when zoomed out")
    func testStopVisibilityThreshold() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.currentDistance = 4_000
        #expect(!viewModel.areStopsVisible)

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(viewModel.stops.isEmpty)
        #expect(provider.callCount == 0)

        viewModel.currentDistance = 2_000
        #expect(viewModel.areStopsVisible)

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)

        viewModel.currentDistance = 5_000
        #expect(!viewModel.areStopsVisible)
        viewModel.loadStopsForSelectedCity()
        #expect(viewModel.stops.isEmpty)
    }

    @Test("Camera position persistence in InMemoryCameraPersistenceStore and restoration on launch")
    func testCameraPersistenceAndRestoration() {
        let store = InMemoryCameraPersistenceStore()
        let provider = StubStopsProvider()

        let vm = MapViewModel(apiClient: provider, initialCity: .warsaw, persistence: store)
        vm.currentCenter = CLLocationCoordinate2D(latitude: 52.235, longitude: 21.015)
        vm.currentDistance = 14_200
        vm.saveCameraPosition()

        let saved = store.loadSavedCamera()
        #expect(saved?.latitude == 52.235)
        #expect(saved?.longitude == 21.015)
        #expect(saved?.distance == 14_200)

        store.saveLastSelectedCityID("warsaw")
        let restoredVM = MapViewModel(apiClient: provider, persistence: store)
        #expect(restoredVM.selectedCity.id == "warsaw")
        #expect(abs(restoredVM.currentCenter.latitude - 52.235) < 1e-6)
        #expect(abs(restoredVM.currentCenter.longitude - 21.015) < 1e-6)
        #expect(restoredVM.currentDistance == 14_200)

        let fallbackStore = InMemoryCameraPersistenceStore(
            initialCityID: "warsaw",
            savedCamera: (latitude: 50.0647, longitude: 19.9450, distance: 10_000)
        )
        let fallbackVM = MapViewModel(apiClient: provider, persistence: fallbackStore)
        #expect(fallbackVM.selectedCity.id == "warsaw")
        #expect(abs(fallbackVM.currentCenter.latitude - City.warsaw.coordinate.latitude) < 1e-6)
        #expect(abs(fallbackVM.currentCenter.longitude - City.warsaw.coordinate.longitude) < 1e-6)

        let pkpStore = InMemoryCameraPersistenceStore(
            initialCityID: "pkp",
            savedCamera: (latitude: 50.0647, longitude: 19.9450, distance: 15_000)
        )
        let pkpVM = MapViewModel(apiClient: provider, persistence: pkpStore)
        #expect(pkpVM.selectedCity.id == "pkp")
        #expect(abs(pkpVM.currentCenter.latitude - 50.0647) < 1e-6)
        #expect(abs(pkpVM.currentCenter.longitude - 19.9450) < 1e-6)
        #expect(pkpVM.currentDistance == 15_000)
    }

    @Test("Buffered region containment and hysteresis correctly identifies safe viewport boundaries")
    func testBufferedRegionContainment() {
        let center = CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01)
        let viewport = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let buffered = MapViewModel.bufferedRegion(for: viewport)

        // The viewport itself is safely contained inside its own buffered region
        #expect(MapViewModel.isRegion(viewport, safelyContainedIn: buffered) == true)

        // A small pan (e.g. 5% shift) is still safely contained
        let smallPan = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.232, longitude: 21.012),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        #expect(MapViewModel.isRegion(smallPan, safelyContainedIn: buffered) == true)

        // A large pan outside the buffer bounds is NOT safely contained
        let largePan = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.26, longitude: 21.01),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        #expect(MapViewModel.isRegion(largePan, safelyContainedIn: buffered) == false)

        // A significant zoom-in (span shrunk by > 20%) triggers re-thinning even if centered
        let zoomedIn = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        #expect(MapViewModel.isRegion(zoomedIn, safelyContainedIn: buffered) == false)
    }

    @Test("Panning within buffered boundary preserves rendered stops without churn")
    func testPanningWithinBufferDoesNotChurnStops() async throws {
        let count = 50
        var allStops: [Stop] = []
        for index in 0..<count {
            allStops.append(
                StopFixtures.sample(
                    id: String(format: "buf-stop-%03d", index),
                    longitude: 21.01 + Double(index) * 0.0002,
                    latitude: 52.23 + Double(index) * 0.0002
                )
            )
        }

        let provider = StubStopsProvider(stops: allStops)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.currentDistance = 2_000

        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        viewModel.loadStopsForSelectedCity()
        try await waitUntilLoaded(viewModel)

        let initialStops = viewModel.stops
        #expect(!initialStops.isEmpty)

        // Small camera pan within the 25% buffered region
        viewModel.applyCameraState(
            MapViewModel.CameraState(
                region: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 52.232, longitude: 21.012),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ),
                heading: 0,
                pitch: 0,
                distance: viewModel.currentDistance,
                center: CLLocationCoordinate2D(latitude: 52.232, longitude: 21.012)
            )
        )

        // Wait a brief moment to ensure no background task altered stops
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.stops == initialStops)
    }
}

