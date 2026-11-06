import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import Testing

@Suite("City Catalog Tests")
@MainActor
struct CityCatalogTests {
    @Test("City catalog contains major Polish networks")
    func testCityCatalog() {
        #expect(City.allCities.contains(where: { $0.id == "warsaw" }))
        #expect(City.allCities.contains(where: { $0.id == "krakow" }))
        #expect(City.allCities.contains(where: { $0.id == "wroclaw" }))
        #expect(City.allCities.contains(where: { $0.id == "poznan" }))
        #expect(City.allCities.contains(where: { $0.id == "tricity" }))
        #expect(City.allCities.contains(where: { $0.id == "gzm" }))
        // 2P6-4: Assert catalog integrity invariant rather than hard-coding a fragile literal count
        #expect(City.allCities.count >= 50)
        #expect(Set(City.allCities.map(\.id)).count == City.allCities.count)
    }

    @Test("City search matches names, IDs, aliases, and diacritic-free queries")
    func testCityAliases() throws {
        let tricity = try #require(City.city(id: "tricity"))
        #expect(tricity.matches(searchText: "trojmiasto"))
        #expect(tricity.matches(searchText: "gdansk"))
        #expect(tricity.matches(searchText: "GDAŃSK"))
        #expect(tricity.matches(searchText: "Trójmiasto"))

        let lodz = try #require(City.city(id: "lodz"))
        #expect(lodz.matches(searchText: "lodz"))
        #expect(lodz.matches(searchText: "Łódź"))

        #expect(City.warsaw.matches(searchText: "warszawa"))
        #expect(City.warsaw.matches(searchText: "") == true)

        // 2P4-6: Missing or typo'd city id returns nil rather than silently returning Warsaw
        #expect(City.city(id: "nonexistent_city") == nil)
    }
}
