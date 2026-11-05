import CoreLocation
import Foundation

/// A supported transit network.
///
/// The catalog lives in the bundled `Resources/cities.json` resource so adding
/// a city is a data change, not a code change. Identity is the API `id`; the
/// custom `==`/`hash` guarantee that two records with the same ID compare
/// equal even if other fields (names, aliases) change between releases.
public struct City: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D
    public let defaultLatitudeDelta: Double
    public let defaultLongitudeDelta: Double
    /// Extra search terms (e.g. `gdansk` for `tricity`, diacritic-free forms).
    public let aliases: [String]

    public init(
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

    public init(from decoder: Decoder) throws {
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
    public func matches(searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if name.localizedStandardContains(query) { return true }
        if id.localizedStandardContains(query) { return true }
        return aliases.contains { $0.localizedStandardContains(query) }
    }

    public static func == (lhs: City, rhs: City) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Catalog

    public static let allCities: [City] = CityCatalog.loadedCities

    /// Convenience references for call sites and tests.
    public static var warsaw: City { city(id: "warsaw") }
    public static var krakow: City { city(id: "krakow") }

    public static func city(id: String) -> City {
        allCities.first { $0.id == id } ?? CityCatalog.fallbackCity
    }
}

/// Loads the bundled city catalog. A malformed or missing resource degrades to
/// a single Warsaw entry (and logs) rather than crashing at launch.
private enum CityCatalog {
    struct CityFile: Decodable {
        let cities: [City]
    }

    static let fallbackCity = City(
        id: "warsaw",
        name: "Warszawa",
        coordinate: CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
    )

    static let loadedCities: [City] = load()

    private static func load() -> [City] {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CityFile.self, from: data),
              !file.cities.isEmpty
        else {
            return [fallbackCity]
        }
        return file.cities
    }
}
