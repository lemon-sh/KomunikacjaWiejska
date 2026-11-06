import CoreLocation
import Foundation
import os

/// A supported transit network.
///
/// The catalog lives in the bundled `Resources/cities.json` resource so adding
/// a city is a data change, not a code change. Identity is the API `id`; the
/// custom `==`/`hash` guarantee that two records with the same ID compare
/// equal even if other fields (names, aliases) change between releases.
struct City: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let defaultLatitudeDelta: Double
    let defaultLongitudeDelta: Double
    /// Extra search terms (e.g. `gdansk` for `tricity`, diacritic-free forms).
    let aliases: [String]

    init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        defaultLatitudeDelta: Double = 0.08,
        defaultLongitudeDelta: Double = 0.08,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.defaultLatitudeDelta = defaultLatitudeDelta
        self.defaultLongitudeDelta = defaultLongitudeDelta
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case latitudeDelta
        case longitudeDelta
        case aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "City \(id): invalid coordinate pair (\(longitude), \(latitude))"
            ))
        }
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.defaultLatitudeDelta = try container.decodeIfPresent(Double.self, forKey: .latitudeDelta) ?? 0.08
        self.defaultLongitudeDelta = try container.decodeIfPresent(Double.self, forKey: .longitudeDelta) ?? 0.08
        self.aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    /// Case- and diacritic-insensitive search across name, ID, and aliases.
    func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if name.localizedStandardContains(query) { return true }
        if id.localizedStandardContains(query) { return true }
        return aliases.contains { $0.localizedStandardContains(query) }
    }

    static func == (lhs: City, rhs: City) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Estimated coverage radius in metres for this transit network.
    ///
    /// For local metropolitan networks, the coverage radius approximates the transit agency's
    /// geographic service area (spanning beyond the downtown core, roughly 1.5× the default viewing span,
    /// bounded at a minimum of 20 km).
    /// Returns 0 for nationwide networks like PKP to prevent false-positive region switches.
    var coverageRadiusMeters: Double {
        if id == "pkp" { return 0 }
        return max(20_000, defaultLatitudeDelta * MapConstants.metresPerDegreeLatitude * 1.5)
    }

    // MARK: - Catalog

    static let allCities: [City] = CityCatalog.loadedCities

    /// Convenience references for call sites and tests.
    static var warsaw: City { city(id: "warsaw") ?? CityCatalog.fallbackCity }
    static var krakow: City { city(id: "krakow") ?? CityCatalog.fallbackCity }
    static var pkp: City { city(id: "pkp") ?? CityCatalog.fallbackCity }

    /// Looks up a city in the catalog by exact id, returning `nil` if not found.
    static func city(id: String) -> City? {
        allCities.first { $0.id == id }
    }
}

/// Loads the bundled city catalog. A malformed or missing resource degrades to
/// a single Warsaw entry and logs the failure rather than crashing at launch.
enum CityCatalog {
    struct CityFile: Decodable {
        let cities: [City]
    }

    static let fallbackCity = City(
        id: "warsaw",
        name: "Warszawa",
        coordinate: CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
    )

    static let loadedCities: [City] = load()

    static func load() -> [City] {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json") else {
            Logger.catalog.error("Failed to locate cities.json in main bundle; falling back to Warsaw.")
            return [fallbackCity]
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(CityFile.self, from: data)
            guard !file.cities.isEmpty else {
                Logger.catalog.error("cities.json contains empty city list; falling back to Warsaw.")
                return [fallbackCity]
            }
            return file.cities
        } catch {
            Logger.catalog.error("Failed to load/decode cities.json: \(error.localizedDescription); falling back to Warsaw.")
            return [fallbackCity]
        }
    }
}
