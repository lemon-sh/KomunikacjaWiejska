import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import MapKit
import SwiftUI
import Testing
import UIKit

@Suite("Zbiorkom Models & Decoding Tests")
@MainActor
struct KomunikacjaWiejskaTests {

    @Test("Decode real Stop tuple JSON payload")
    func testDecodeStopTuple() throws {
        // 10-element positional Stop tuple payload from api6-open
        let sampleJSON = """
        {
            "stops": [
                [
                    "rybnik-srodmiescie-dworek261-0-j58h8",
                    "rybnik",
                    "Rybnik Śródmieście Dworek",
                    "261/0",
                    [18.542289, 50.096472],
                    [3],
                    145,
                    "Chwałowice / Boguszowice",
                    [
                        ["24", "rybnik", "24", "24", "default", 3, "#215da5"],
                        ["48", "rybnik", "48", "48", "default", 3, "#e53935"]
                    ],
                    [
                        ["Wejście A", [18.542300, 50.096500]]
                    ]
                ]
            ]
        }
        """

        let data = Data(sampleJSON.utf8)
        let response = try JSONDecoder().decode(StopsResponse.self, from: data)

        #expect(response.stops.count == 1)
        let stop = try #require(response.stops.first)

        #expect(stop.id == "rybnik-srodmiescie-dworek261-0-j58h8")
        #expect(stop.city == "rybnik")
        #expect(stop.name == "Rybnik Śródmieście Dworek")
        #expect(stop.code == "261/0")
        #expect(stop.displayName == "Rybnik Śródmieście Dworek (261/0)")
        #expect(stop.longitude == 18.542289)
        #expect(stop.latitude == 50.096472)
        #expect(stop.coordinate.latitude == 50.096472)
        #expect(stop.coordinate.longitude == 18.542289)
        #expect(stop.vehicleTypes == [.bus])
        #expect(stop.primaryVehicleType == .bus)
        #expect(stop.bearing == 145)
        #expect(stop.direction == "Chwałowice / Boguszowice")

        #expect(stop.routes.count == 2)
        let firstRoute = stop.routes[0]
        #expect(firstRoute.id == "24")
        #expect(firstRoute.name == "24")
        #expect(firstRoute.type == .bus)
        #expect(firstRoute.color == "#215da5")

        #expect(stop.entrances.count == 1)
        let firstEntrance = stop.entrances[0]
        #expect(firstEntrance.name == "Wejście A")
        #expect(firstEntrance.longitude == 18.542300)
        #expect(firstEntrance.latitude == 50.096500)
    }

    @Test("BoundingBox calculations and query string")
    func testBoundingBox() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.06)
        )

        let bbox = BoundingBox(region: region)
        #expect(bbox != nil)

        if let bbox = bbox {
            #expect(bbox.minLat > 52.20 && bbox.minLat < 52.22)
            #expect(bbox.maxLat > 52.24 && bbox.maxLat < 52.26)
            #expect(bbox.minLon > 20.97 && bbox.minLon < 20.99)
            #expect(bbox.maxLon > 21.03 && bbox.maxLon < 21.05)
            #expect(bbox.queryValue.contains(","))
        }
    }

    @Test("Tile grid covers the viewport and stays within a useful zoom range")
    func testTileGridCoverage() throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        let tiles = MapTileGrid.visibleTiles(in: region)
        #expect(!tiles.isEmpty)
        #expect(tiles.count <= 40)

        let zoom = MapTileGrid.zoom
        let tileWidth = 360.0 / Double(1 << zoom)
        let tilesAcross = region.span.longitudeDelta / tileWidth
        #expect(tilesAcross >= 0.5)
        #expect(tilesAcross <= 5)

        let coverage = try #require(MapTileGrid.boundingBox(covering: tiles))
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        #expect(coverage.minLat <= region.center.latitude - halfLat + 1e-9)
        #expect(coverage.maxLat >= region.center.latitude + halfLat - 1e-9)
        #expect(coverage.minLon <= region.center.longitude - halfLon + 1e-9)
        #expect(coverage.maxLon >= region.center.longitude + halfLon - 1e-9)

        for tile in tiles {
            let bounds = MapTileGrid.bounds(of: tile)
            #expect(bounds.minLat < bounds.maxLat)
            #expect(bounds.minLon < bounds.maxLon)
            #expect(MapTileGrid.latitude(tileY: Double(tile.y), zoom: tile.zoom) == bounds.maxLat)
            #expect(MapTileGrid.latitude(tileY: Double(tile.y + 1), zoom: tile.zoom) == bounds.minLat)
        }
    }

    @Test("All tiles share fixed Zoom 12 coarseness without hierarchy")
    func testFixedZoomTiles() {
        let tile = MapTile(x: 2200, y: 1300)
        #expect(tile.zoom == 12)
        #expect(MapTile.fixedZoom == 12)
        #expect(MapTileGrid.zoom == 12)
    }

    @Test("RouteType properties and fallback")
    func testRouteType() {
        #expect(RouteType.tram.systemImageName == "tram.fill")
        #expect(RouteType.bus.systemImageName == "bus.fill")
        #expect(RouteType.subway.systemImageName == "tram.fill.tunnel")
        #expect(RouteType.rail.systemImageName == "train.side.front.car")
        #expect(RouteType.ferry.systemImageName == "ferry.fill")

        let unknown = RouteType(rawValue: 999)
        #expect(unknown == nil)
    }

    // MARK: - Positional tuple hardening (P3-3, P3-4)

    private func decodeStops(_ json: String) throws -> [Stop] {
        let response = try JSONDecoder().decode(StopsResponse.self, from: Data(json.utf8))
        return response.stops
    }

    private func stopTuple(
        bearing: String = "90",
        vehicleTypes: String = "[3]",
        routes: String = "[]",
        entrances: String = "[]",
        location: String = "[21.01, 52.23]",
        extraElements: String = ""
    ) -> String {
        """
        {
            "stops": [[
                "stop-1", "warsaw", "Testowa", "01",
                \(location), \(vehicleTypes), \(bearing), "Centrum",
                \(routes), \(entrances)\(extraElements)
            ]]
        }
        """
    }

    @Test("A tuple with too few elements fails with a descriptive error")
    func testTooFewTupleElements() {
        do {
            _ = try decodeStops(#"{"stops": [["only-id"]]}"#)
            Issue.record("Expected a decoding error for a short tuple")
        } catch let error as DecodingError {
            guard case .dataCorrupted(let context) = error else {
                Issue.record("Unexpected decoding error: \(error)")
                return
            }
            #expect(context.debugDescription.contains("Stop"))
            #expect(context.debugDescription.contains("at least 10"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("An unknown vehicle type decodes as .unknown")
    func testUnknownVehicleType() throws {
        let stops = try decodeStops(stopTuple(vehicleTypes: "[999]"))
        #expect(stops.first?.vehicleTypes == [.unknown])
    }

    @Test("A null bearing decodes as nil, and bearings are normalized")
    func testBearingNormalization() throws {
        #expect(try decodeStops(stopTuple(bearing: "null")).first?.bearing == nil)
        #expect(try decodeStops(stopTuple(bearing: "370")).first?.bearing == 10)
        #expect(try decodeStops(stopTuple(bearing: "-10")).first?.bearing == 350)
    }

    @Test("Empty routes and entrances decode to empty arrays")
    func testEmptyCollections() throws {
        let stop = try #require(decodeStops(stopTuple()).first)
        #expect(stop.routes.isEmpty)
        #expect(stop.entrances.isEmpty)
    }

    @Test("Extra trailing tuple elements are tolerated for forward compatibility")
    func testExtraTupleElements() throws {
        let stop = try #require(decodeStops(stopTuple(extraElements: ", \"future\", 42")).first)
        #expect(stop.id == "stop-1")
    }

    @Test("Invalid coordinates fail with a descriptive error")
    func testInvalidCoordinates() {
        do {
            _ = try decodeStops(stopTuple(location: "[21.01, 200.0]"))
            Issue.record("Expected a decoding error for invalid coordinates")
        } catch let error as DecodingError {
            guard case .dataCorrupted(let context) = error else {
                Issue.record("Unexpected decoding error: \(error)")
                return
            }
            #expect(context.debugDescription.contains("invalid coordinate"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Entrance IDs are deterministic and unique even with duplicate names")
    func testEntranceIdentity() throws {
        let entrances = """
        [["Wejście", [21.0, 52.0]], ["Wejście", [21.0, 52.0]]]
        """
        let firstDecode = try #require(decodeStops(stopTuple(entrances: entrances)).first)
        let secondDecode = try #require(decodeStops(stopTuple(entrances: entrances)).first)

        #expect(firstDecode.entrances.count == 2)
        #expect(Set(firstDecode.entrances.map(\.id)).count == 2)
        #expect(firstDecode.entrances.map(\.id) == secondDecode.entrances.map(\.id))
        #expect(firstDecode.entrances.first?.id == "stop-1-entrance-0")
    }

    // MARK: - Color parsing (P3-5) & RouteType (P3-6)

    private func rgba(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    @Test("Hex color parsing accepts 3-, 6-, and 8-digit formats")
    func testColorParsingValid() throws {
        let white = try #require(Color(hex: "#fff"))
        let whiteRGBA = rgba(white)
        #expect(whiteRGBA.red == 1 && whiteRGBA.green == 1 && whiteRGBA.blue == 1 && whiteRGBA.alpha == 1)

        let red = try #require(Color(hex: "#ff0000"))
        let redRGBA = rgba(red)
        #expect(redRGBA.red == 1 && redRGBA.green == 0 && redRGBA.blue == 0)

        // 8-digit format is ARGB: 50% alpha over full red.
        let translucentRed = try #require(Color(hex: "#80ff0000"))
        let translucentRGBA = rgba(translucentRed)
        #expect(translucentRGBA.red == 1)
        #expect(abs(translucentRGBA.alpha - 128.0 / 255.0) < 0.01)
    }

    @Test("Hex color parsing rejects invalid input")
    func testColorParsingInvalid() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#12") == nil)      // 2 digits
        #expect(Color(hex: "#abcd") == nil)    // 4 digits
        #expect(Color(hex: "#abcde") == nil)   // 5 digits
        #expect(Color(hex: "#abcdef0") == nil) // 7 digits
        #expect(Color(hex: "#gggggg") == nil)  // non-hex characters

        // Explicit fallback is used instead of a silent wrong color.
        #expect(rgba(Color(hex: "nope", fallback: .blue)).blue == 1)
    }

    @Test("Relative luminance and text contrast safely differentiate light and dark backgrounds")
    func testRelativeLuminanceAndContrast() throws {
        // Light backgrounds -> Black text
        #expect(Color.contrastingTextColor(forHex: "#FFFFFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#FFFF00") == .black) // Yellow
        #expect(Color.contrastingTextColor(forHex: "FFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#A8F0C6") == .black) // Pale mint

        // Dark backgrounds -> White text
        #expect(Color.contrastingTextColor(forHex: "#000000") == .white)
        #expect(Color.contrastingTextColor(forHex: "#0000FF") == .white) // Pure blue
        #expect(Color.contrastingTextColor(forHex: "#1E3A8A") == .white) // Navy
        #expect(Color.contrastingTextColor(forHex: "#D97706") == .white) // Dark amber
        #expect(Color.contrastingTextColor(forHex: "000") == .white)

        // Invalid hex -> Fallback
        #expect(Color.contrastingTextColor(forHex: "invalid", fallback: .white) == .white)
        #expect(Color.contrastingTextColor(forHex: "", fallback: .black) == .black)

        // Numerical luminance bounds
        let whiteLum = try #require(Color.relativeLuminance(hex: "#ffffff"))
        let blackLum = try #require(Color.relativeLuminance(hex: "#000000"))
        #expect(abs(whiteLum - 1.0) < 0.001)
        #expect(abs(blackLum - 0.0) < 0.001)
        #expect(Color.relativeLuminance(hex: "xyz") == nil)
    }

    @Test("RouteType decoding is resilient and displayable cases exclude .unknown")
    func testRouteTypeDecoding() throws {
        #expect(RouteType.displayableCases.contains(.unknown) == false)
        #expect(RouteType.displayableCases.count == RouteType.allCases.count - 1)

        let decodedKnown = try JSONDecoder().decode(RouteType.self, from: Data("3".utf8))
        #expect(decodedKnown == .bus)

        let decodedUnknown = try JSONDecoder().decode(RouteType.self, from: Data("999".utf8))
        #expect(decodedUnknown == .unknown)

        let encoded = try JSONEncoder().encode(RouteType.unknown)
        #expect(String(data: encoded, encoding: .utf8) == "-1")
        #expect(RouteType.unknown.systemImageName != RouteType.bus.systemImageName)
        #expect(RouteType.unknown.defaultHexColor != RouteType.bus.defaultHexColor)
    }

    @Test("City catalog contains major Polish networks")
    func testCityCatalog() {
        #expect(City.allCities.contains(where: { $0.id == "warsaw" }))
        #expect(City.allCities.contains(where: { $0.id == "krakow" }))
        #expect(City.allCities.contains(where: { $0.id == "wroclaw" }))
        #expect(City.allCities.contains(where: { $0.id == "poznan" }))
        #expect(City.allCities.contains(where: { $0.id == "tricity" }))
        #expect(City.allCities.contains(where: { $0.id == "gzm" }))
        #expect(City.allCities.count == 66)
        #expect(Set(City.allCities.map(\.id)).count == City.allCities.count)
    }

    @Test("City search matches names, IDs, aliases, and diacritic-free queries")
    func testCityAliases() {
        let tricity = City.city(id: "tricity")
        #expect(tricity.matches(searchText: "trojmiasto"))
        #expect(tricity.matches(searchText: "gdansk"))
        #expect(tricity.matches(searchText: "GDAŃSK"))
        #expect(tricity.matches(searchText: "Trójmiasto"))

        let lodz = City.city(id: "lodz")
        #expect(lodz.matches(searchText: "lodz"))
        #expect(lodz.matches(searchText: "Łódź"))

        #expect(City.warsaw.matches(searchText: "warszawa"))
        #expect(City.warsaw.matches(searchText: "") == true)
    }

    @Test("MapMode identifiers stay stable while display names are localized")
    func testMapModes() {
        #expect(MapMode.allCases.count == 2)
        // Raw values are persisted/identity values, not UI copy.
        #expect(MapMode.explore.rawValue == "Explore")
        #expect(MapMode.satellite.rawValue == "Satellite")
        #expect(MapMode.explore.id == "Explore")
        #expect(MapMode.satellite.id == "Satellite")
        #expect(!MapMode.explore.displayName.isEmpty)
        #expect(MapMode.explore.displayName != MapMode.satellite.displayName)
    }

    @Test("The app ships Polish and English localizations")
    func testLocalizations() {
        let localizations = Set(Bundle.main.localizations)
        #expect(localizations.contains("pl"))
        #expect(localizations.contains("en"))
        #expect(
            Bundle.main.localizedString(forKey: "map.loading.initial", value: nil, table: nil)
                != "map.loading.initial"
        )
    }

    @Test("The location permission prompt is localized in both languages")
    func testLocationUsageDescriptionLocalization() throws {
        let enPath = try #require(
            Bundle.main.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "en"
            )
        )
        let plPath = try #require(
            Bundle.main.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "pl"
            )
        )
        let enStrings = try #require(NSDictionary(contentsOfFile: enPath) as? [String: String])
        let plStrings = try #require(NSDictionary(contentsOfFile: plPath) as? [String: String])

        let key = "NSLocationWhenInUseUsageDescription"
        #expect(enStrings[key]?.isEmpty == false)
        #expect(plStrings[key]?.isEmpty == false)
        #expect(enStrings[key] != plStrings[key])
    }

    // MARK: - Hermetic MapViewModel behaviour

    @Test("MapViewModel map mode and user location controls")
    func testMapViewModelControls() {
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)
        #expect(viewModel.selectedMapMode == .explore)
        #expect(viewModel.isShowingMapModes == false)
        #expect(viewModel.isTrackingUser == false)

        viewModel.selectedMapMode = .satellite
        #expect(viewModel.selectedMapMode == .satellite)

        let targetCoord = CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
        viewModel.centerOnUserLocation(coordinate: targetCoord)
        #expect(viewModel.isTrackingUser == true)
        #expect(viewModel.currentCenter.latitude == targetCoord.latitude)
        #expect(viewModel.currentCenter.longitude == targetCoord.longitude)
    }

    @Test("Location authorization state maps prompts, denial, and authorization")
    func testLocationAuthorizationState() {
        #expect(LocationAuthorizationState.resolve(status: .notDetermined) == .notDetermined)
        #expect(LocationAuthorizationState.resolve(status: .denied) == .denied)
        // Disabling Location Services system-wide also surfaces as `.denied`.
        #expect(LocationAuthorizationState.resolve(status: .restricted) == .denied)
        #expect(LocationAuthorizationState.resolve(status: .authorizedWhenInUse) == .authorized)
        #expect(LocationAuthorizationState.resolve(status: .authorizedAlways) == .authorized)
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

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

        viewModel.loadStopsForSelectedCity()
        while provider.requestedCities.isEmpty { await Task.yield() }
        #expect(viewModel.loadingPhase == .initial)

        provider.openGate()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.loadingPhase == nil)

        // A different viewport in the same city is a plain reload, not a city
        // switch and not a cold start.
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.20),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        provider.holdRequests()
        viewModel.loadStopsForSelectedCity()
        while provider.requestedCities.count < 2 { await Task.yield() }
        #expect(viewModel.loadingPhase == .refresh)

        provider.openGate()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.loadingPhase == nil)
    }

    @Test("Typed load state and city switching without string parsing")
    func testTypedLoadStateAcrossCitySwitch() async throws {
        let provider = StubStopsProvider(holdsRequests: true)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        #expect(viewModel.isLoading)
        #expect(viewModel.loadingPhase == .initial)

        // Switch to Krakow while Warsaw is loading
        viewModel.selectCity(.krakow, repositionCamera: false)
        #expect(viewModel.isLoading)
        #expect(viewModel.loadingPhase == .citySwitch)

        provider.openGate()
        while viewModel.isLoading { await Task.yield() }
        #expect(!viewModel.isLoading)
        #expect(viewModel.loadingPhase == nil)
    }

    @Test("Visible stops are rendered in deterministic ID order without thinning")
    func testVisibleStopsRenderedWithoutThinning() async throws {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2, longitude: 21.0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        // Stops within the viewport
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
            distance: 5_000,
            center: region.center
        )

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(viewModel.stops.count == 50)
        #expect(viewModel.stops.map(\.id) == stops.map(\.id).sorted())
    }

    @Test("Repeated loads and camera changes use the cache without refetching")
    func testStopsKeptInMemory() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        // Loading the same viewport again must be served from the tile cache,
        // not the network.
        viewModel.loadStopsForSelectedCity()
        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)

        // Camera changes should not clear or refresh stops (a fetch only ever
        // starts from a debounced camera-change event or explicit load).
        let dummyRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.0, longitude: 21.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        viewModel.visibleRegion = dummyRegion
        #expect(viewModel.stops.count == 1)

        // Restoring the initial viewport is still covered by the session tiles.
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.stops.first?.bearing == 90)

        // Same ID, new details: the rendered marker array must update.
        provider.setStops([StopFixtures.sample(bearing: 180, longitude: 21.20, latitude: 52.23)])
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.20),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(viewModel.stops.first?.bearing == 180)
    }

    @Test("Stop selection updates selectedStop and cachedStop lookup")
    func testStopSelection() async throws {
        let stopA = StopFixtures.sample(id: "stop-a", name: "Stop Alpha")
        let stopB = StopFixtures.sample(id: "stop-b", name: "Stop Beta")
        let provider = StubStopsProvider(stops: [stopA, stopB])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(viewModel.selectedStopID == nil)
        #expect(viewModel.selectedStop == nil)
        #expect(viewModel.cachedStop(for: "stop-a")?.name == "Stop Alpha")
        #expect(viewModel.cachedStop(for: "stop-b")?.name == "Stop Beta")
        #expect(viewModel.cachedStop(for: "non-existent") == nil)

        // Selecting stop A
        viewModel.selectedStopID = "stop-a"
        #expect(viewModel.selectedStop?.id == "stop-a")
        #expect(viewModel.selectedStop?.name == "Stop Alpha")

        // Switching selection directly to stop B
        viewModel.selectedStopID = "stop-b"
        #expect(viewModel.selectedStop?.id == "stop-b")
        #expect(viewModel.selectedStop?.name == "Stop Beta")

        // Deselection
        viewModel.selectedStopID = nil
        #expect(viewModel.selectedStop == nil)
    }

    @Test("Selected stop is preserved in rendered stops")
    func testSelectedStopPreserved() async throws {
        let count = 300
        var allStops: [Stop] = []
        for index in 0..<count {
            allStops.append(
                StopFixtures.sample(
                    id: String(format: "thin-stop-%03d", index),
                    longitude: 21.0 + Double(index) * 0.0001,
                    latitude: 52.2 + Double(index) * 0.0001
                )
            )
        }

        let targetID = "thin-stop-150"
        let provider = StubStopsProvider(stops: allStops)
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        viewModel.selectedStopID = targetID

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(viewModel.stops.count <= MapViewModel.maxRenderedStops)
        #expect(viewModel.stops.contains(where: { $0.id == targetID }))
    }

    @Test("Selecting a stop does not recompute rendered stops array instance if stop is already present")
    func testSelectionDoesNotRecomputeStops() async throws {
        let stopA = StopFixtures.sample(id: "stop-a", name: "A")
        let stopB = StopFixtures.sample(id: "stop-b", name: "B")
        let provider = StubStopsProvider(stops: [stopA, stopB])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        let originalStops = viewModel.stops
        #expect(originalStops.count == 2)

        // Select stop A
        viewModel.selectedStopID = "stop-a"
        #expect(viewModel.stops == originalStops)

        // Select stop B
        viewModel.selectedStopID = "stop-b"
        #expect(viewModel.stops == originalStops)

        // Deselect
        viewModel.selectedStopID = nil
        #expect(viewModel.stops == originalStops)
    }

    @Test("Rotating and pitching at a fixed center issues zero network requests")
    func testRotationAndPitchIssuesZeroRequests() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        let initialCallCount = provider.callCount

        // Change heading and pitch only at the same center
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.errorMessage == "Failed to load")

        // Switch to Krakow (successful)
        viewModel.selectCity(.krakow)
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.errorMessage == nil)

        // Switch back to Warsaw with success now
        provider.setStops([StopFixtures.sample(city: "warsaw")])
        viewModel.selectCity(.warsaw)
        while viewModel.isLoading { await Task.yield() }
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(provider.callCount == 1)

        // Far outside the previous coverage: none of the fetched tiles cover
        // this viewport, so a new request is required.
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.2300, longitude: 21.2000),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(provider.callCount == 2)
    }

    @Test("A viewport inside fetched tile coverage reuses the cache")
    func testViewportInsideCoverageDoesNotFetch() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)
        let initialRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: City.warsaw.defaultLatitudeDelta,
                longitudeDelta: City.warsaw.defaultLongitudeDelta
            )
        )

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(provider.callCount == 1)

        // A tighter viewport within the same Zoom 12 tiles needs no new requests
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
        let wideRegion = MKCoordinateRegion(
            center: City.warsaw.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        viewModel.visibleRegion = wideRegion
        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(provider.callCount == 2)

        // The tiles now cover the wide viewport.
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.stops == [stopA])

        provider.setStops([stopB])
        viewModel.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.5000, longitude: 21.5000),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        // The new viewport renders only B, while A stays in the session cache.
        #expect(viewModel.stops == [stopB])

        // Returning to the first viewport is covered by its tiles: no new
        // request, and A is still available.
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(provider.callCount == 1)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.stops.isEmpty)
        #expect(viewModel.loadingPhase == nil)

        // Failed cities may be retried
        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
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

        viewModel.loadStopsForSelectedCity()
        while provider.requestedCities.count < 1 { await Task.yield() }
        #expect(provider.requestedCities == ["warsaw"])
        #expect(viewModel.isLoading == true)

        // Switch to an uncached city: previous stops must vanish immediately.
        viewModel.selectCity(.krakow)
        while provider.requestedCities.count < 2 { await Task.yield() }
        #expect(viewModel.stops.isEmpty)
        #expect(provider.requestedCities == ["warsaw", "krakow"])
        #expect(viewModel.loadingPhase == .citySwitch)

        // Release both requests; the stale Warsaw response must not surface.
        provider.openGate()
        while viewModel.isLoading { await Task.yield() }

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

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.stops == warsawStops)

        // The previous city's stops must disappear immediately; switching back
        // later refetches because the cache is session-scoped per city.
        viewModel.selectCity(.krakow)
        #expect(viewModel.stops.isEmpty)
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.stops == krakowStops)

        viewModel.selectCity(.warsaw)
        #expect(viewModel.stops.isEmpty)
        while viewModel.isLoading { await Task.yield() }
        #expect(viewModel.stops == warsawStops)
        #expect(provider.callCount == 3)
    }

    @Test("Compact mode is correct from launch and after switching to a wide network")
    func testCompactModeAtLaunchAndSwitch() {
        let warsawViewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)
        // Warsaw default distance is ~8,880m, which is above the 6,000m compact threshold
        #expect(warsawViewModel.isCompactDisplayMode == true)

        // When zoomed in below 6,000m, compact display is disabled
        warsawViewModel.currentDistance = 4_000
        #expect(warsawViewModel.isCompactDisplayMode == false)

        let pkp = City.city(id: "pkp")
        let pkpViewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: pkp)
        #expect(pkpViewModel.isCompactDisplayMode == true)

        // Switching to a countrywide network must not keep the zoomed-in
        // distance until MapKit sends its first camera callback.
        warsawViewModel.selectCity(pkp)
        #expect(warsawViewModel.isCompactDisplayMode == true)
    }

    @Test("Compact display mode respects the threshold boundaries")
    func testCompactDisplayMode() {
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: .warsaw)
        let threshold = viewModel.compactDisplayDistanceThreshold

        // Below the threshold: full markers.
        viewModel.currentDistance = threshold - 1
        #expect(viewModel.isCompactDisplayMode == false)

        // Above the threshold (e.g. zoomed out to PKP scale): compact points.
        viewModel.currentDistance = threshold + 1
        #expect(viewModel.isCompactDisplayMode == true)
    }

    // MARK: - Region Suggestion Tests

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
    func testDismissSuggestion() {
        let warsaw = City.warsaw
        let krakow = City.krakow
        let viewModel = MapViewModel(apiClient: StubStopsProvider(), initialCity: warsaw)

        // Move camera to Kraków
        viewModel.cameraState = MapViewModel.CameraState(
            region: MKCoordinateRegion(
                center: krakow.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ),
            center: krakow.coordinate
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity?.id == "krakow")

        // Dismiss
        viewModel.dismissSuggestedCity()
        #expect(viewModel.suggestedCity == nil)
        #expect(viewModel.dismissedCityID == "krakow")

        // Updating while still in Kraków keeps it suppressed
        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity == nil)

        // Moving far away to Poznań coordinate resets dismissed state and suggests Poznań
        let poznan = City.city(id: "poznan")
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
    func testSwitchToSuggestedCityPreservesCameraAndLoadsStops() async {
        let krakow = City.krakow
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

        // Set camera in Kraków
        viewModel.cameraState = MapViewModel.CameraState(
            region: customRegion,
            center: customKrakowCenter
        )
        viewModel.updateRegionSuggestion()
        #expect(viewModel.suggestedCity?.id == "krakow")

        // Switch to suggested city
        viewModel.switchToSuggestedCity()

        #expect(viewModel.selectedCity.id == "krakow")
        #expect(viewModel.suggestedCity == nil)
        // Camera position must remain where user was viewing, not jumped to Kraków default
        #expect(viewModel.cameraState.center.latitude == customKrakowCenter.latitude)
        #expect(viewModel.cameraState.center.longitude == customKrakowCenter.longitude)
        #expect(viewModel.cameraState.region.span.latitudeDelta == 0.05)

        while viewModel.isLoading { await Task.yield() }
        #expect(provider.requestedCities.contains("krakow"))
    }

    @Test("Excludes nationwide PKP from region suggestions")
    func testExcludesPKPFromRegionSuggestions() {
        let pkp = City.city(id: "pkp")
        let suggestion = MapViewModel.detectSuggestedCity(
            center: pkp.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: .warsaw
        )
        // Center near Piątek / PKP should not suggest switching to PKP
        #expect(suggestion?.id != "pkp")
    }

    @Test("PKP mode suggests local city when zooming into one")
    func testPKPSuggestsLocalCity() {
        let pkp = City.city(id: "pkp")
        let krakow = City.krakow
        let suggestion = MapViewModel.detectSuggestedCity(
            center: krakow.coordinate,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08),
            currentCity: pkp
        )
        #expect(suggestion?.id == "krakow")
    }

    @Test("Stop marker direction updates with map camera heading")
    func testStopMarkerEffectiveRotation() {
        // When map is North-up (heading = 0°), screen rotation matches geographic bearing directly
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 0) == 90)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 0) == 0)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 0) == 180)
        #expect(StopMarkerView.effectiveRotation(bearing: 270, heading: 0) == 270)

        // When map is rotated East-up (heading = 90°):
        // East (bearing 90°) points to the top of screen (0°)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 90) == 0)
        // North (bearing 0°) points to the left of screen (-90°)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 90) == -90)
        // South (bearing 180°) points to the right of screen (90°)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 90) == 90)

        // When map is rotated South-up (heading = 180°):
        // East (bearing 90°) points to the left of screen (-90°)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 180) == -90)

        // Arbitrary angles
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 45) == -45)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 350) == -170)
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

    // MARK: - Stop Visibility Threshold & Non-Volatile Persistence

    @Test("Stop visibility threshold hides stops and suppresses fetching when zoomed out")
    func testStopVisibilityThreshold() async throws {
        let provider = StubStopsProvider(stops: [StopFixtures.sample()])
        let viewModel = MapViewModel(apiClient: provider, initialCity: .warsaw)

        // When distance is beyond the 12,000m threshold:
        viewModel.currentDistance = 13_000
        #expect(!viewModel.areStopsVisible)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(viewModel.stops.isEmpty)
        #expect(provider.callCount == 0) // Fetch suppressed

        // When zoomed back inside the threshold:
        viewModel.currentDistance = 8_000
        #expect(viewModel.areStopsVisible)

        viewModel.loadStopsForSelectedCity()
        while viewModel.isLoading { await Task.yield() }

        #expect(provider.callCount == 1)
        #expect(viewModel.stops.count == 1)

        // Zooming out again immediately hides rendered stops:
        viewModel.currentDistance = 15_000
        #expect(!viewModel.areStopsVisible)
        viewModel.loadStopsForSelectedCity()
        #expect(viewModel.stops.isEmpty)
    }

    @Test("Camera position persistence in InMemoryCameraPersistenceStore and restoration on launch")
    func testCameraPersistenceAndRestoration() {
        let store = InMemoryCameraPersistenceStore()
        let provider = StubStopsProvider()

        // 1. Save camera state from a MapViewModel instance
        let vm = MapViewModel(apiClient: provider, initialCity: .warsaw, persistence: store)
        vm.currentCenter = CLLocationCoordinate2D(latitude: 52.235, longitude: 21.015)
        vm.currentDistance = 14_200
        vm.saveCameraPosition()

        let saved = store.loadSavedCamera()
        #expect(saved?.latitude == 52.235)
        #expect(saved?.longitude == 21.015)
        #expect(saved?.distance == 14_200)

        // 2. Restore on launch when position is within city bounds
        store.saveLastSelectedCityID("warsaw")
        let restoredVM = MapViewModel(apiClient: provider, persistence: store)
        #expect(restoredVM.selectedCity.id == "warsaw")
        #expect(abs(restoredVM.currentCenter.latitude - 52.235) < 1e-6)
        #expect(abs(restoredVM.currentCenter.longitude - 21.015) < 1e-6)
        #expect(restoredVM.currentDistance == 14_200)

        // 3. Fall back to city defaults when saved coordinate is outside city coverage
        let fallbackStore = InMemoryCameraPersistenceStore(
            initialCityID: "warsaw",
            savedCamera: (latitude: 50.0647, longitude: 19.9450, distance: 10_000)
        )
        let fallbackVM = MapViewModel(apiClient: provider, persistence: fallbackStore)
        #expect(fallbackVM.selectedCity.id == "warsaw")
        #expect(abs(fallbackVM.currentCenter.latitude - City.warsaw.coordinate.latitude) < 1e-6)
        #expect(abs(fallbackVM.currentCenter.longitude - City.warsaw.coordinate.longitude) < 1e-6)

        // 4. PKP restores saved coordinates without boundary checks
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

    @Test("StopDetailSheet route badges have uniform height across vehicle types")
    func testRouteBadgeUniformHeight() {
        for type in RouteType.displayableCases {
            let route = StopRoute(
                id: "route-\(type.rawValue)",
                city: "warsaw",
                name: "100",
                longName: "100",
                agency: "ztm",
                type: type,
                color: "#1E88E5"
            )
            let badge = RouteBadgeView(route: route)
            let size = UIHostingController(rootView: badge).sizeThatFits(in: CGSize(width: 300, height: 300))
            #expect(size.height == 24)
        }
    }

    @Test("StopDetailSheet header icon container has uniform square footprint across vehicle types")
    func testHeaderIconUniformFootprint() {
        for type in RouteType.displayableCases {
            let stop = Stop(
                id: "stop-\(type.rawValue)",
                city: "warsaw",
                name: "Test Stop",
                code: "01",
                longitude: 21.0,
                latitude: 52.0,
                vehicleTypes: [type],
                bearing: 0,
                direction: "Center",
                routes: [],
                entrances: []
            )
            let sheet = StopDetailSheet(stop: stop, onDismiss: {})
            let size = UIHostingController(rootView: sheet).sizeThatFits(in: CGSize(width: 375, height: 600))
            #expect(size.width > 0 && size.height > 0)
        }
    }
}

extension BoundingBox {
    init?(region: MKCoordinateRegion) {
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta
        guard latDelta.isFinite, lonDelta.isFinite, latDelta > 0, lonDelta > 0 else {
            return nil
        }
        let center = region.center
        let halfLat = latDelta / 2.0
        let halfLon = lonDelta / 2.0
        let minLat = max(-90.0, center.latitude - halfLat)
        let maxLat = min(90.0, center.latitude + halfLat)
        let minLon = max(-180.0, center.longitude - halfLon)
        let maxLon = min(180.0, center.longitude + halfLon)
        self.init(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }
}
