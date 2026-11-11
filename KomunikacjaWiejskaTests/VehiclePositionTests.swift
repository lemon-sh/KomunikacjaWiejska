import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import Testing

@Suite("VehiclePosition Model Tests")
struct VehiclePositionTests {
    @Test("Decodes VehiclePosition JSON correctly from API payload")
    func testDecodeVehiclePosition() throws {
        let json = """
        {
            "vehicle": {
                "id": "2025",
                "type": "3",
                "agency": "default",
                "model": "Solbus SM18"
            },
            "routeName": "189",
            "routeColor": "#a5248c",
            "brigade": "D31",
            "location": [20.908178, 52.228401],
            "timestamp": 1794335632000,
            "bearing": 84,
            "delay": 120000,
            "headsign": "Rondo Unii Europejskiej",
            "upcomingStops": [
                {
                    "sequence": 1,
                    "name": "Hala Wola",
                    "scheduledArrival": 1794334320000,
                    "scheduledDeparture": 1794334320000
                }
            ],
            "url": "https://v6-api.zbiorkom-v5.pages.dev/warsaw/vehicle/3%3A2025"
        }
        """.data(using: .utf8)!

        let vehicle = try JSONDecoder().decode(VehiclePosition.self, from: json)

        #expect(vehicle.id == "default:3:2025")
        #expect(vehicle.routeName == "189")
        #expect(vehicle.routeColor == "#a5248c")
        #expect(vehicle.brigade == "D31")
        #expect(vehicle.bearing == 84)
        #expect(vehicle.delay == 120000)
        #expect(vehicle.delayMinutes == 2)
        #expect(vehicle.delaySeconds == 120)
        #expect(vehicle.headsign == "Rondo Unii Europejskiej")
        #expect(vehicle.routeType == .bus)
        #expect(abs(vehicle.coordinate.latitude - 52.228401) < 1e-5)
        #expect(abs(vehicle.coordinate.longitude - 20.908178) < 1e-5)
        #expect(vehicle.upcomingStops.count == 1)
        #expect(vehicle.upcomingStops[0].name == "Hala Wola")
    }

    @Test("Decodes VehiclesResponse wrapper")
    func testDecodeVehiclesResponse() throws {
        let json = """
        {
            "positions": [
                {
                    "vehicle": {
                        "id": "59",
                        "type": "0",
                        "agency": "ztm",
                        "model": null
                    },
                    "routeName": "4",
                    "routeColor": "#ff0000",
                    "brigade": "2",
                    "location": [21.0, 52.2],
                    "timestamp": 1794335632000,
                    "bearing": null,
                    "delay": 0,
                    "headsign": null,
                    "upcomingStops": [],
                    "url": ""
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(VehiclesResponse.self, from: json)
        #expect(response.positions.count == 1)
        let first = response.positions[0]
        #expect(first.id == "ztm:0:59")
        #expect(first.routeType == .tram)
        #expect(first.bearing == nil)
        #expect(first.headsign == nil)
    }

    @Test("Equatable checks position, rotation, and upcoming stops")
    func testEquatable() {
        let v1 = VehicleFixtures.sample(id: "1", longitude: 21.0, latitude: 52.0)
        let v2 = VehicleFixtures.sample(id: "1", longitude: 21.0, latitude: 52.0)
        let v3 = VehicleFixtures.sample(id: "1", longitude: 21.1, latitude: 52.0)
        let v4 = VehicleFixtures.sample(
            id: "1",
            longitude: 21.0,
            latitude: 52.0,
            upcomingStops: [
                VehicleUpcomingStop(sequence: 1, name: "Centrum", scheduledArrival: 1_700_000_060_000, scheduledDeparture: 1_700_000_060_000)
            ]
        )

        #expect(v1 == v2)
        #expect(v1 != v3)
        #expect(v1 != v4)
    }
}
