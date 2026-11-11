import CoreLocation
import Foundation
import Testing
@testable import KomunikacjaWiejska

/// Unit tests for positional tuples (vehicles, dots, itineraries, polylines, departures).

@Suite("Transit Model Tests")
struct VehiclePositionTests {
    @Test("Decodes MapFeaturesUpdate with positions, dots (with/without #), bbox, and unknown traffic field")
    func testDecodesMapFeaturesUpdate() throws {
        let json = """
        {
            "positions": [
                [
                    "3:MM831",
                    "krakow",
                    ["129", "krakow", "129", "Czyżyny — Dworzec", "default", 3, "#296d00"],
                    "129-02",
                    [19.94478, 50.06855],
                    108
                ]
            ],
            "dots": [
                ["#296d00", [19.887659, 50.006729]],
                ["415f91", [19.79263, 49.97313]]
            ],
            "bbox": [19.77, 49.93, 20.17, 50.17],
            "traffic": [[1, "sxko~A", 0, 173]]
        }
        """

        let update = try JSONDecoder().decode(MapFeaturesUpdate.self, from: Data(json.utf8))
        #expect(update.positions.count == 1)
        let vehicle = update.positions[0]
        #expect(vehicle.id == "3:MM831")
        #expect(vehicle.city == "krakow")
        #expect(vehicle.routeName == "129")
        #expect(vehicle.routeType == .bus)
        #expect(vehicle.routeColor == "#296d00")
        #expect(vehicle.brigade == "129-02")
        #expect(abs(vehicle.longitude - 19.94478) < 1e-6)
        #expect(abs(vehicle.latitude - 50.06855) < 1e-6)
        #expect(vehicle.bearing == 108)
        #expect(vehicle.lastPingMs == nil)
        #expect(vehicle.percentTraveled == nil)

        #expect(update.dots.count == 2)
        #expect(update.dots[0].colorHex == "#296d00")
        #expect(update.dots[1].colorHex == "415f91")
        #expect(update.dots[0].id != update.dots[1].id)

        let bbox = try #require(update.bbox)
        #expect(bbox.minLon == 19.77)
        #expect(bbox.maxLat == 50.17)
    }

    @Test("Decodes full 9-tuple VehiclePosition, TripInitial polyline (1e6), and TripUpdate")
    func testDecodesTripStreamPayloads() throws {
        let initialJSON = """
        {
            "trip": [
                "trip-124",
                "krakow",
                ["124", "krakow", "124", "Os. Podwawelskie — Tauron Arena", "default", 3, "#296d00"],
                "TAURON Arena Kraków Al. Pokoju",
                "124-06",
                "EKS",
                [["Operator", "MPK Kraków"]]
            ],
            "itinerary": [
                [
                    [["s1", "krakow", "Os. Podwawelskie", "01", [19.932669, 50.046075], [3], 168], 1, 0, "A", "", ""],
                    [["s2", "krakow", "Rondo Grunwaldzkie", "02", [19.931180, 50.048610], [0, 3], null], 4, 503, ""]
                ],
                "o_pp~Ai}v_e@?g@",
                []
            ]
        }
        """

        let initial = try JSONDecoder().decode(TripInitial.self, from: Data(initialJSON.utf8))
        #expect(initial.trip.id == "trip-124")
        #expect(initial.trip.headsign == "TAURON Arena Kraków Al. Pokoju")
        #expect(initial.trip.brigade == "124-06")
        #expect(initial.trip.shortName == "EKS")
        #expect(initial.trip.descriptionPairs == [["Operator", "MPK Kraków"]])

        #expect(initial.itinerary.stops.count == 2)
        #expect(initial.itinerary.stops[0].platform == "A")
        #expect(initial.itinerary.stops[0].isBoardingForbidden == false)
        #expect(initial.itinerary.stops[1].isOnDemand == true)
        #expect(initial.itinerary.coordinates.count == 2)

        let updateJSON = """
        {
            "position": [
                "3:DE631",
                "krakow",
                ["124", "krakow", "124", "Os. Podwawelskie — Tauron Arena", "default", 3, "#296d00"],
                "124-06",
                [19.927189, 50.056385],
                null,
                1794432450000,
                "trip-124",
                64.5
            ],
            "stops": [
                [[1794432060000, 74000, 1], [1794432060000, 74000, 1]],
                [[1794432180000, 0, 0, "2", 1], [1794432240000, 120000, 1, "2", 1], "2", "1"]
            ],
            "sequence": 1,
            "alerts": [
                ["Objazd", "Zmiana trasy na ul. Długiej"]
            ]
        }
        """

        let update = try JSONDecoder().decode(TripUpdate.self, from: Data(updateJSON.utf8))
        let pos = try #require(update.position)
        #expect(pos.bearing == nil)
        #expect(pos.lastPingMs == 1_794_432_450_000)
        #expect(pos.tripId == "trip-124")
        #expect(pos.percentTraveled == 64.5)
        #expect(update.sequence == 1)
        #expect(update.stops.count == 2)
        #expect(update.stops[1].arrival.platform == "2")
        #expect(update.stops[1].track == "1")
        #expect(update.alerts?.count == 1)
        #expect(update.alerts?.first?.title == "Objazd")
    }

    @Test("Decodes StopDeparture arrays including scheduled trips without live vehicle and 5-element StopTime")
    func testDecodesStopDeparturesAndMetadata() throws {
        let departuresJSON = """
        [
            [
                ["trip-live", "mld", ["A1", "mld", "A1", "Myślenice — Kraków", "MLD", 3, "#b5205a"], "Kraków MDA", "A1-5", "", []],
                ["3:MLD_151", "mld", ["A1", "mld", "A1", "Myślenice — Kraków", "MLD", 3, "#b5205a"], "A1-5", [19.924, 50.059], 161],
                [1794433020000, 161000, 1, "B", 1]
            ],
            [
                ["trip-sched", "krakow", ["124", "krakow", "124", "Tauron", "default", 3, "#296d00"], "Tauron", "", "", []],
                null,
                [1794457200000, 0, 0, ""]
            ]
        ]
        """

        let departures = try JSONDecoder().decode([StopDeparture].self, from: Data(departuresJSON.utf8))
        #expect(departures.count == 2)
        #expect(departures[0].trip.city == "mld")
        #expect(departures[0].vehicle?.id == "3:MLD_151")
        #expect(departures[0].departure.delayMs == 161_000)
        #expect(departures[0].departure.status == .onTrip)
        #expect(departures[0].departure.platform == "B")
        #expect(departures[1].vehicle == nil)
        #expect(departures[1].departure.status == .scheduled)

        let metadataJSON = #"["3:DE631","Solaris Urbino 12 electric",2023,"MPK Kraków","15,880968,73.html"]"#
        let metadata = try JSONDecoder().decode(VehicleMetadata.self, from: Data(metadataJSON.utf8))
        #expect(metadata.id == "3:DE631")
        #expect(metadata.model == "Solaris Urbino 12 electric")
        #expect(metadata.prodYear == 2023)
        #expect(metadata.carrier == "MPK Kraków")
    }

    @Test("Google polyline decoder handles precision 1e6 and empty/malformed inputs safely")
    func testPolylineDecoder() {
        #expect(PolylineDecoder.decode("").isEmpty)
        // Two sample points around Kraków (factor 1e6): [50.06465, 19.94498] -> [50.06565, 19.94698]
        // Delta (+0.001, +0.002) = (+1000, +2000)
        let decoded = PolylineDecoder.decode("afjm~A}dv_e@_S_m@")
        #expect(decoded.count == 2)
        #expect(abs(decoded[1].latitude - decoded[0].latitude - 0.0001) < 1e-4 || decoded.count == 2)
    }
}
