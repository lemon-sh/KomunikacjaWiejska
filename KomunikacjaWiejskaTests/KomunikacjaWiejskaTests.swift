import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import MapKit
import Testing

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

    @Test("City catalog contains major Polish networks")
    func testCityCatalog() {
        #expect(City.allCities.contains(where: { $0.id == "warsaw" }))
        #expect(City.allCities.contains(where: { $0.id == "krakow" }))
        #expect(City.allCities.contains(where: { $0.id == "wroclaw" }))
        #expect(City.allCities.contains(where: { $0.id == "poznan" }))
        #expect(City.allCities.contains(where: { $0.id == "tricity" }))
        #expect(City.allCities.contains(where: { $0.id == "gzm" }))
    }

    @Test("MapMode enum cases and initialization")
    func testMapModes() {
        #expect(MapMode.allCases.count == 2)
        #expect(MapMode.explore.rawValue == "Explore")
        #expect(MapMode.satellite.rawValue == "Satellite")
        #expect(MapMode.explore.id == "Explore")
        #expect(MapMode.satellite.id == "Satellite")
    }

    @Test("MapViewModel map mode and user location controls")
    func testMapViewModelControls() {
        let viewModel = MapViewModel(initialCity: .warsaw)
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

    @Test("Stops are loaded once and kept in memory without refreshing on camera updates")
    func testStopsKeptInMemory() {
        let viewModel = MapViewModel(initialCity: .warsaw)

        let mockStop = Stop(
            id: "test-stop",
            city: "warsaw",
            name: "Testowa",
            code: "01",
            longitude: 21.01,
            latitude: 52.23,
            vehicleTypes: [.bus],
            bearing: 90,
            direction: "Centrum",
            routes: [],
            entrances: []
        )

        viewModel.stops = [mockStop]
        #expect(viewModel.stops.count == 1)

        // Camera changes should not clear or refresh stops
        let dummyRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.0, longitude: 21.0),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        viewModel.visibleRegion = dummyRegion
        viewModel.loadStopsForSelectedCity()
        #expect(viewModel.stops.count == 1)
        #expect(viewModel.isZoomedOutForStops == false)
        #expect(viewModel.isCompactDisplayMode == true)

        let zoomedInRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.23, longitude: 21.01),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        viewModel.visibleRegion = zoomedInRegion
        #expect(viewModel.isCompactDisplayMode == false)
    }
}
