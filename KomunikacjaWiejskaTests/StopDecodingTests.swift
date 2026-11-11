import CoreLocation
import Foundation
import Testing
@testable import KomunikacjaWiejska

/// Unit tests for positional `Stop` decoding (7-tuple `mapFeatures` and 10-tuple stop stream).

@Suite("Stop Decoding Tests")
struct StopDecodingTests {
    private func stopTuple(
        id: String = "stop-1",
        city: String = "warsaw",
        name: String = "Centrum",
        code: String = "261/0",
        longitude: Double = 21.01,
        latitude: Double = 52.23,
        vehicleTypes: String = "[3]",
        bearing: String = "180",
        direction: String = "Plac Wolności",
        routes: String = #"[{"id":"ignored"}]"#,
        entrances: String = #"[]"# ,
        extraElements: String = ""
    ) -> String {
        let defaultRoutes = routes == #"[{"id":"ignored"}]"#
            ? ##"[["128", "warsaw", "128", "Szczęśliwice", "ZTM", 3, "#e00"]]"##
            : routes
        return """
        {
            "stops": [
                [
                    "\(id)", "\(city)", "\(name)", "\(code)",
                    [\(longitude), \(latitude)],
                    \(vehicleTypes), \(bearing), "\(direction)",
                    \(defaultRoutes), \(entrances)\(extraElements)
                ]
            ]
        }
        """
    }

    private func decodeStops(_ json: String) throws -> [Stop] {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(MapFeaturesInitial.self, from: data).stops
    }

    @Test("Decodes 7-tuple mapFeatures stop without trailing metadata")
    func testDecodesSevenTupleMapFeaturesStop() throws {
        let json = """
        {
            "stops": [
                ["stary-kleparz03-xjma3", "krakow", "Stary Kleparz", "03", [19.938954, 50.066654], [0, 3], 167]
            ],
            "suggestedCity": "krakow"
        }
        """
        let initial = try JSONDecoder().decode(MapFeaturesInitial.self, from: Data(json.utf8))
        #expect(initial.suggestedCity == "krakow")
        #expect(initial.stops.count == 1)

        let stop = initial.stops[0]
        #expect(stop.id == "stary-kleparz03-xjma3")
        #expect(stop.city == "krakow")
        #expect(stop.name == "Stary Kleparz")
        #expect(stop.code == "03")
        #expect(abs(stop.longitude - 19.938954) < 1e-6)
        #expect(abs(stop.latitude - 50.066654) < 1e-6)
        #expect(stop.vehicleTypes == [.tram, .bus])
        #expect(stop.primaryVehicleType == .tram)
        #expect(stop.bearing == 167)
        #expect(stop.direction.isEmpty)
        #expect(stop.routes.isEmpty)
        #expect(stop.entrances.isEmpty)
        #expect(stop.hasFullMetadata == false)
    }

    @Test("Decodes full 10-tuple stop from stops/{id}/stream")
    func testDecodesValidStop() throws {
        let entrances = #" [["Wyjście 01", [21.02, 52.24]]] "#
        let json = stopTuple(entrances: entrances)
        let response = try JSONDecoder().decode(MapFeaturesInitial.self, from: Data(json.utf8))

        #expect(response.stops.count == 1)
        let stop = try #require(response.stops.first)
        #expect(stop.id == "stop-1")
        #expect(stop.city == "warsaw")
        #expect(stop.name == "Centrum")
        #expect(stop.code == "261/0")
        #expect(stop.longitude == 21.01)
        #expect(stop.latitude == 52.23)
        #expect(stop.coordinate.longitude == 21.01)
        #expect(stop.coordinate.latitude == 52.23)
        #expect(stop.vehicleTypes == [.bus])
        #expect(stop.primaryVehicleType == .bus)
        #expect(stop.bearing == 180)
        #expect(stop.direction == "Plac Wolności")
        #expect(stop.hasFullMetadata == true)

        #expect(stop.routes.count == 1)
        let route = stop.routes[0]
        #expect(route.id == "128")
        #expect(route.city == "warsaw")
        #expect(route.name == "128")
        #expect(route.longName == "Szczęśliwice")
        #expect(route.agency == "ZTM")
        #expect(route.type == .bus)
        #expect(route.color == "#e00")

        #expect(stop.entrances.count == 1)
        let firstEntrance = stop.entrances[0]
        #expect(firstEntrance.name == "Wyjście 01")
        #expect(firstEntrance.longitude == 21.02)
        #expect(firstEntrance.latitude == 52.24)
        #expect(firstEntrance.coordinate.longitude == 21.02)
        #expect(firstEntrance.coordinate.latitude == 52.24)
    }

    @Test("Stop primaryVehicleType defaults to unknown and isRailOrSubway detects metro/rail")
    func testEmptyVehicleTypesAndRailDetection() {
        let emptyStop = Stop(
            id: "empty-types",
            city: "warsaw",
            name: "Unknown Pole",
            code: "01",
            latitude: 52.23,
            longitude: 21.01,
            vehicleTypes: [],
            bearing: nil
        )
        #expect(emptyStop.primaryVehicleType == .unknown)
        #expect(emptyStop.isRailOrSubway == false)

        let metroStop = Stop(
            id: "metro",
            city: "warsaw",
            name: "Centrum",
            code: "",
            latitude: 52.23,
            longitude: 21.01,
            vehicleTypes: [.subway],
            bearing: nil
        )
        #expect(metroStop.isRailOrSubway == true)
    }

    @Test("Truncated stop tuple (<7 fields) throws TupleDecodingError")
    func testTruncatedStopThrowsError() {
        let truncated = #"{ "stops": [["only-1", "warsaw"]] }"#
        #expect(throws: TupleDecodingError.self) {
            try decodeStops(truncated)
        }
    }

    @Test("Unknown route types map to .unknown without failing stop decoding")
    func testUnknownVehicleType() throws {
        let tuple = stopTuple(vehicleTypes: "[999]")
        let stop = try #require(decodeStops(tuple).first)
        #expect(stop.vehicleTypes == [.unknown])
        #expect(stop.primaryVehicleType == .unknown)
    }

    @Test("Null and out-of-range bearings normalize cleanly")
    func testBearingNormalization() throws {
        let nullBearingStop = try #require(decodeStops(stopTuple(bearing: "null")).first)
        #expect(nullBearingStop.bearing == nil)

        let wrapPositiveStop = try #require(decodeStops(stopTuple(bearing: "450")).first)
        #expect(wrapPositiveStop.bearing == 90)

        let wrapNegativeStop = try #require(decodeStops(stopTuple(bearing: "-90")).first)
        #expect(wrapNegativeStop.bearing == 270)
    }

    @Test("Empty routes and entrances decode to empty arrays")
    func testEmptyCollections() throws {
        let stop = try #require(decodeStops(stopTuple(routes: "[]", entrances: "[]")).first)
        #expect(stop.routes.isEmpty)
        #expect(stop.entrances.isEmpty)
    }

    @Test("Extra trailing tuple elements are tolerated for forward compatibility")
    func testExtraTupleElements() throws {
        let stop = try #require(decodeStops(stopTuple(extraElements: #", "future_field_1", 42, {"k":"v"}"#)).first)
        #expect(stop.id == "stop-1")
    }

    @Test("Invalid coordinates fail with TupleDecodingError")
    func testInvalidCoordinates() {
        let badLon = stopTuple(longitude: 200.0, latitude: 52.0)
        #expect(throws: TupleDecodingError.self) { try decodeStops(badLon) }

        let badLat = stopTuple(longitude: 21.0, latitude: -95.0)
        #expect(throws: TupleDecodingError.self) { try decodeStops(badLat) }
    }

    @Test("Entrance IDs are deterministic and unique even with duplicate names")
    func testEntranceIdentity() throws {
        let entrances = """
        [
            ["Brama 1", [21.01, 52.23]],
            ["Brama 1", [21.02, 52.24]]
        ]
        """
        let firstDecode = try #require(decodeStops(stopTuple(entrances: entrances)).first)
        let secondDecode = try #require(decodeStops(stopTuple(entrances: entrances)).first)

        #expect(firstDecode.entrances.count == 2)
        #expect(Set(firstDecode.entrances.map(\.id)).count == 2)
        #expect(firstDecode.entrances.map(\.id) == secondDecode.entrances.map(\.id))
        #expect(firstDecode.entrances.first?.id == "stop-1-entrance-0")
        #expect(firstDecode.entrances.last?.id == "stop-1-entrance-1")
    }

    @Test("RouteType decoding falls back safely and displayableCases excludes .unknown")
    func testRouteTypeDecoding() throws {
        #expect(RouteType.displayableCases.contains(.unknown) == false)
        #expect(RouteType.displayableCases.count == RouteType.allCases.count - 1)

        let decodedKnown = try JSONDecoder().decode(RouteType.self, from: Data("3".utf8))
        #expect(decodedKnown == .bus)

        let decodedUnknown = try JSONDecoder().decode(RouteType.self, from: Data("999".utf8))
        #expect(decodedUnknown == .unknown)
    }
}
