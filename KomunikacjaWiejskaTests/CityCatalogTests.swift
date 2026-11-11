import Foundation
import Testing
@testable import KomunikacjaWiejska

/// Catalog tests covering dynamic `/api6` city decoding, filtering, and search.

@Suite("City Catalog Tests")
struct CityCatalogTests {
    @Test("Picker cities exclude virtual meta-networks while lookup includes them")
    func testPickerExcludesVirtualNetworks() {
        let catalog = StubStopsProvider.sampleCities
        let picker = City.pickerCities(from: catalog)
        #expect(!picker.contains(where: { $0.isVirtual }))
        #expect(picker.contains(where: { $0.id == "warsaw" }))
        #expect(City.city(id: "pkp", in: catalog)?.isVirtual == true)
        #expect(City.city(id: "mld", in: catalog)?.isVirtual == true)
        #expect(City.city(id: "nonexistent_city", in: catalog) == nil)
    }

    @Test("City search matches IDs, descriptions, aliases, agencies, and Polish diacritics")
    func testCityLookupAndSearch() throws {
        let catalog = StubStopsProvider.sampleCities
        let tricity = try #require(City.city(id: "tricity", in: catalog))
        #expect(tricity.matches(searchText: "gdansk"))
        #expect(tricity.matches(searchText: "GDAŃSK"))
        #expect(tricity.matches(searchText: "Gdynia"))
        #expect(tricity.matches(searchText: "Warszawa") == false)

        let lodz = try #require(City.city(id: "lodz", in: catalog))
        #expect(lodz.matches(searchText: "lodz"))
        #expect(lodz.matches(searchText: "Łódź"))

        let warsaw = StubStopsProvider.sampleWarsaw
        #expect(warsaw.matches(searchText: "warszawa"))
        #expect(warsaw.matches(searchText: "WTP"))
        #expect(warsaw.matches(searchText: "") == true)
    }

    @Test("Decodes GET /api6 CitiesResponse with location, timezone, virtual flag, and agencies")
    func testDecodesDynamicApi6CitiesResponse() throws {
        let json = """
        {
            "hash": "abc123",
            "shouldUpdate": true,
            "cities": [
                {
                    "id": "helsinki",
                    "name": "Helsinki",
                    "description": "HSL",
                    "category": "finland",
                    "location": [24.941561, 60.170811],
                    "timezone": "Europe/Helsinki",
                    "agencies": {
                        "default": { "id": "default", "name": "HSL", "faresUrl": "https://hsl.fi" }
                    }
                },
                {
                    "id": "pkp",
                    "name": "PKP",
                    "location": [21.035, 52.255],
                    "virtual": true
                }
            ]
        }
        """

        let response = try JSONDecoder().decode(CitiesResponse.self, from: Data(json.utf8))
        #expect(response.cities.count == 2)
        let helsinki = response.cities[0]
        #expect(helsinki.id == "helsinki")
        #expect(abs(helsinki.longitude - 24.941561) < 1e-6)
        #expect(abs(helsinki.latitude - 60.170811) < 1e-6)
        #expect(helsinki.timeZone.identifier == "Europe/Helsinki")
        #expect(helsinki.agencies["default"]?.faresUrl == "https://hsl.fi")
        #expect(helsinki.isVirtual == false)
        #expect(response.cities[1].isVirtual == true)
    }
}
