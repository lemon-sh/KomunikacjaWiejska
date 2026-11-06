import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import Testing

@Suite("Stop & Route Tuple Decoding Tests")
@MainActor
struct StopDecodingTests {
    private func stopTuple(
        id: String = "stop-1",
        city: String = "warsaw",
        name: String = "Centrum",
        code: String = "01",
        longitude: Double = 21.01,
        latitude: Double = 52.23,
        vehicleTypes: String = "[3]",
        bearing: String = "90",
        direction: String = "Dw. Centralny",
        routes: String = "[]",
        entrances: String = "[]",
        extraElements: String = ""
    ) -> String {
        """
        [
            "\(id)", "\(city)", "\(name)", "\(code)",
            [\(longitude), \(latitude)],
            \(vehicleTypes), \(bearing), "\(direction)",
            \(routes), \(entrances)\(extraElements)
        ]
        """
    }

    private func decodeStops(_ json: String) throws -> [Stop] {
        let payload = "{\"stops\":[\(json)]}"
        let data = try #require(payload.data(using: .utf8))
        return try JSONDecoder().decode(StopsResponse.self, from: data).stops
    }

    @Test("Decode real Stop tuple JSON payload")
    func testDecodeStopTuple() throws {
        let json = """
        {
            "stops": [
                [
                    "rybnik-srodmiescie-dworek261-0-j58h8",
                    "rybnik",
                    "Rybnik Śródmieście Dworek",
                    "261/0",
                    [18.542289, 50.096472],
                    [3],
                    180,
                    "Plac Wolności",
                    [
                        [
                            "rybnik-route-a",
                            "rybnik",
                            "A",
                            "Linia A",
                            "ZTZ Rybnik",
                            3,
                            "FB8C00"
                        ]
                    ],
                    [
                        [
                            "Wejście A",
                            [18.542300, 50.096500]
                        ]
                    ]
                ]
            ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(StopsResponse.self, from: data)

        #expect(response.stops.count == 1)
        let stop = response.stops[0]
        #expect(stop.id == "rybnik-srodmiescie-dworek261-0-j58h8")
        #expect(stop.city == "rybnik")
        #expect(stop.name == "Rybnik Śródmieście Dworek")
        #expect(stop.code == "261/0")
        #expect(stop.longitude == 18.542289)
        #expect(stop.latitude == 50.096472)
        #expect(stop.coordinate.longitude == 18.542289)
        #expect(stop.coordinate.latitude == 50.096472)
        #expect(stop.vehicleTypes == [.bus])
        #expect(stop.primaryVehicleType == .bus)
        #expect(stop.bearing == 180)
        #expect(stop.direction == "Plac Wolności")
        #expect(stop.displayName == "Rybnik Śródmieście Dworek (261/0)")

        #expect(stop.routes.count == 1)
        let route = stop.routes[0]
        #expect(route.id == "rybnik-route-a")
        #expect(route.city == "rybnik")
        #expect(route.name == "A")
        #expect(route.longName == "Linia A")
        #expect(route.agency == "ZTZ Rybnik")
        #expect(route.type == .bus)
        #expect(route.color == "FB8C00")

        #expect(stop.entrances.count == 1)
        let firstEntrance = stop.entrances[0]
        #expect(firstEntrance.name == "Wejście A")
        #expect(firstEntrance.longitude == 18.542300)
        #expect(firstEntrance.latitude == 50.096500)
        #expect(firstEntrance.coordinate.longitude == 18.542300)
        #expect(firstEntrance.coordinate.latitude == 50.096500)
    }

    @Test("Stop primaryVehicleType defaults to unknown when vehicleTypes is empty")
    func testPrimaryVehicleTypeEmpty() {
        let emptyStop = Stop(
            id: "test",
            city: "warsaw",
            name: "Test",
            code: "",
            longitude: 21.0,
            latitude: 52.0,
            vehicleTypes: [],
            bearing: nil,
            direction: "",
            routes: [],
            entrances: []
        )
        #expect(emptyStop.primaryVehicleType == .unknown)
    }

    @Test("A tuple with too few elements fails with a descriptive error")
    func testTooFewTupleElements() {
        let truncated = #"["id", "warsaw", "Centrum", "01"]"#
        #expect(throws: DecodingError.self) {
            try decodeStops(truncated)
        }
    }

    @Test("An unknown vehicle type decodes as .unknown")
    func testUnknownVehicleType() throws {
        let tuple = stopTuple(vehicleTypes: "[999]")
        let stop = try #require(decodeStops(tuple).first)
        #expect(stop.vehicleTypes == [.unknown])
        #expect(stop.primaryVehicleType == .unknown)
    }

    @Test("A null bearing decodes as nil, and bearings are normalized")
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

    @Test("Invalid coordinates fail with a descriptive error")
    func testInvalidCoordinates() {
        let badLon = stopTuple(longitude: 200.0, latitude: 52.0)
        #expect(throws: DecodingError.self) { try decodeStops(badLon) }

        let badLat = stopTuple(longitude: 21.0, latitude: -95.0)
        #expect(throws: DecodingError.self) { try decodeStops(badLat) }
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

    @Test("RouteType decoding is resilient and displayable cases exclude .unknown")
    func testRouteTypeDecoding() throws {
        #expect(RouteType.displayableCases.contains(.unknown) == false)
        #expect(RouteType.displayableCases.count == RouteType.allCases.count - 1)

        let decodedKnown = try JSONDecoder().decode(RouteType.self, from: Data("3".utf8))
        #expect(decodedKnown == .bus)

        let decodedUnknown = try JSONDecoder().decode(RouteType.self, from: Data("999".utf8))
        #expect(decodedUnknown == .unknown)
    }
}
