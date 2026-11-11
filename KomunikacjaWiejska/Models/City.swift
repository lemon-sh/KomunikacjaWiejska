import CoreLocation
import Foundation

/// Dynamic city catalog model decoded from `GET /api6` with cross-city and search metadata.

/// Transit agency metadata returned inside `/api6` city records.
nonisolated struct Agency: Equatable, Hashable, Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let faresUrl: String?
    let icon: String?

    init(id: String, name: String, faresUrl: String? = nil, icon: String? = nil) {
        self.id = id
        self.name = name
        self.faresUrl = faresUrl
        self.icon = icon
    }
}

/// Top-level payload returned by `GET /api6`.
nonisolated struct CitiesResponse: Decodable, Equatable, Sendable {
    let hash: String?
    let shouldUpdate: Bool?
    let cities: [City]
}

/// Transit network / city entry returned by `GET /api6`.
nonisolated struct City: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let latitude: Double
    let longitude: Double
    let timezoneIdentifier: String
    let zoom: Double?
    let showNewTag: Bool
    let disableBrigades: Bool
    let isVirtual: Bool
    let agencies: [String: Agency]
    let coverageRadiusMeters: Double
    let aliases: [String]
    let defaultLatitudeDelta: Double
    let defaultLongitudeDelta: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timezoneIdentifier)
            ?? TimeZone(identifier: "Europe/Warsaw")
            ?? .current
    }

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        description: String? = nil,
        category: String? = nil,
        timezoneIdentifier: String = "Europe/Warsaw",
        zoom: Double? = nil,
        showNewTag: Bool = false,
        disableBrigades: Bool = false,
        isVirtual: Bool = false,
        agencies: [String: Agency] = [:],
        coverageRadiusMeters: Double? = nil,
        aliases: [String] = [],
        defaultLatitudeDelta: Double? = nil,
        defaultLongitudeDelta: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.timezoneIdentifier = timezoneIdentifier
        self.zoom = zoom
        self.showNewTag = showNewTag
        self.disableBrigades = disableBrigades
        self.isVirtual = isVirtual
        self.agencies = agencies
        let defaultCoverageRadius: Double = isVirtual ? 0 : 40_000
        self.coverageRadiusMeters = coverageRadiusMeters ?? defaultCoverageRadius
        self.aliases = aliases
        let defaultDelta: Double = isVirtual ? 3.5 : MapConstants.defaultCoordinateSpanDelta
        self.defaultLatitudeDelta = defaultLatitudeDelta ?? defaultDelta
        self.defaultLongitudeDelta = defaultLongitudeDelta ?? defaultDelta
    }

    func matches(searchText: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let normalizedQuery = Self.normalizedForSearch(trimmed)
        let candidates = [id, name, description ?? ""] + aliases + agencies.values.map(\.name)
        return candidates.contains { candidate in
            !candidate.isEmpty && Self.normalizedForSearch(candidate).contains(normalizedQuery)
        }
    }

    private static func normalizedForSearch(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
    }
}

nonisolated extension City: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case location
        case timezone
        case zoom
        case showNewTag
        case disableBrigades
        case virtual
        case agencies
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        let category = try container.decodeIfPresent(String.self, forKey: .category)
        let location = try container.decode(CoordinatePair.self, forKey: .location)
        let timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Warsaw"
        let zoom = try container.decodeIfPresent(Double.self, forKey: .zoom)
        let showNewTag = try container.decodeIfPresent(Bool.self, forKey: .showNewTag) ?? false
        let disableBrigades = try container.decodeIfPresent(Bool.self, forKey: .disableBrigades) ?? false
        let isVirtual = try container.decodeIfPresent(Bool.self, forKey: .virtual) ?? false
        let agencies = try container.decodeIfPresent([String: Agency].self, forKey: .agencies) ?? [:]

        self.init(
            id: id,
            name: name,
            latitude: location.latitude,
            longitude: location.longitude,
            description: description,
            category: category,
            timezoneIdentifier: timezone,
            zoom: zoom,
            showNewTag: showNewTag,
            disableBrigades: disableBrigades,
            isVirtual: isVirtual,
            agencies: agencies
        )
    }
}

nonisolated extension City {
    static func city(id: String, in catalog: [City]) -> City? {
        catalog.first(where: { $0.id == id })
    }

    /// Mirrors zbiorkom.live CitySelect: excludes virtual meta-networks (`pkp`, `mld`, `lka`, etc.).
    static func pickerCities(from catalog: [City]) -> [City] {
        catalog.filter { !$0.isVirtual }
    }
}
