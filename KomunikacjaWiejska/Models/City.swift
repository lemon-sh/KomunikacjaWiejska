import CoreLocation
import Foundation

/// A supported transit network.
///
/// The catalog is maintained as compile-time static entities in `City.allCities`.
/// Identity is the API `id`; the custom `==`/`hash` guarantee that two records
/// with the same ID compare equal even if other fields (names, aliases) change between releases.
struct City: Identifiable, Hashable, Sendable {
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

    // MARK: - Catalog Constants

    /// Convenience references for call sites and tests.
    static let warsaw = City(
        id: "warsaw",
        name: "Warszawa",
        coordinate: CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122),
        aliases: ["warszawa", "waw"]
    )
    static let krakow = City(
        id: "krakow",
        name: "Kraków",
        coordinate: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.945)
    )
    static let pkp = City(
        id: "pkp",
        name: "PKP (Ogólnopolska Kolej)",
        coordinate: CLLocationCoordinate2D(latitude: 52.0693, longitude: 19.4803),
        defaultLatitudeDelta: 5.0,
        defaultLongitudeDelta: 5.0,
        aliases: ["kolej", "pociag", "pociąg", "rail"]
    )

    // MARK: - Catalog

    static let allCities: [City] = [
        warsaw,
        krakow,
        City(id: "wroclaw", name: "Wrocław", coordinate: CLLocationCoordinate2D(latitude: 51.1079, longitude: 17.0385), aliases: ["wrocław"]),
        City(id: "poznan", name: "Poznań", coordinate: CLLocationCoordinate2D(latitude: 52.4064, longitude: 16.9252), aliases: ["poznań"]),
        City(id: "tricity", name: "Trójmiasto (Gdańsk / Gdynia / Sopot)", coordinate: CLLocationCoordinate2D(latitude: 54.352, longitude: 18.6466), defaultLatitudeDelta: 0.15, defaultLongitudeDelta: 0.15, aliases: ["trojmiasto", "trójmiasto", "gdansk", "gdańsk", "gdynia", "sopot"]),
        City(id: "gzm", name: "Górnośląsko-Zagłębiowska Metropolia (Katowice)", coordinate: CLLocationCoordinate2D(latitude: 50.2649, longitude: 19.0238), defaultLatitudeDelta: 0.15, defaultLongitudeDelta: 0.15, aliases: ["katowice", "metropolia", "gornoslasko-zaglebiowska"]),
        City(id: "lodz", name: "Łódź", coordinate: CLLocationCoordinate2D(latitude: 51.7592, longitude: 19.456), aliases: ["łodź"]),
        City(id: "szczecin", name: "Szczecin", coordinate: CLLocationCoordinate2D(latitude: 53.4285, longitude: 14.5528)),
        City(id: "lublin", name: "Lublin", coordinate: CLLocationCoordinate2D(latitude: 51.2465, longitude: 22.5684)),
        City(id: "bialystok", name: "Białystok", coordinate: CLLocationCoordinate2D(latitude: 53.1325, longitude: 23.1688), aliases: ["białystok"]),
        City(id: "bydgoszcz", name: "Bydgoszcz", coordinate: CLLocationCoordinate2D(latitude: 53.1235, longitude: 18.0084)),
        City(id: "torun", name: "Toruń", coordinate: CLLocationCoordinate2D(latitude: 53.0138, longitude: 18.5984)),
        City(id: "rzeszow", name: "Rzeszów", coordinate: CLLocationCoordinate2D(latitude: 50.0412, longitude: 21.9991)),
        City(id: "kielce", name: "Kielce", coordinate: CLLocationCoordinate2D(latitude: 50.8661, longitude: 20.6286)),
        City(id: "olsztyn", name: "Olsztyn", coordinate: CLLocationCoordinate2D(latitude: 53.7784, longitude: 20.4801)),
        City(id: "opole", name: "Opole", coordinate: CLLocationCoordinate2D(latitude: 50.6751, longitude: 17.9213)),
        City(id: "czestochowa", name: "Częstochowa", coordinate: CLLocationCoordinate2D(latitude: 50.8118, longitude: 19.1203), aliases: ["częstochowa"]),
        City(id: "radom", name: "Radom", coordinate: CLLocationCoordinate2D(latitude: 51.4027, longitude: 21.1471)),
        City(id: "bielsko", name: "Bielsko-Biała", coordinate: CLLocationCoordinate2D(latitude: 49.8224, longitude: 19.0444)),
        City(id: "rybnik", name: "Rybnik", coordinate: CLLocationCoordinate2D(latitude: 50.097, longitude: 18.5418)),
        City(id: "zielonagora", name: "Zielona Góra", coordinate: CLLocationCoordinate2D(latitude: 51.9356, longitude: 15.5062), aliases: ["zielona góra"]),
        City(id: "gorzow", name: "Gorzów Wielkopolski", coordinate: CLLocationCoordinate2D(latitude: 52.7368, longitude: 15.2288), aliases: ["gorzów"]),
        pkp,
        City(id: "elblag", name: "Elbląg", coordinate: CLLocationCoordinate2D(latitude: 54.1561, longitude: 19.4045)),
        City(id: "plock", name: "Płock", coordinate: CLLocationCoordinate2D(latitude: 52.5463, longitude: 19.7065)),
        City(id: "tarnow", name: "Tarnów", coordinate: CLLocationCoordinate2D(latitude: 50.0121, longitude: 20.9858)),
        City(id: "kalisz", name: "Kalisz", coordinate: CLLocationCoordinate2D(latitude: 51.7673, longitude: 18.0853)),
        City(id: "legnica", name: "Legnica", coordinate: CLLocationCoordinate2D(latitude: 51.207, longitude: 16.1553)),
        City(id: "grudziadz", name: "Grudziądz", coordinate: CLLocationCoordinate2D(latitude: 53.4841, longitude: 18.7536)),
        City(id: "jaworzno", name: "Jaworzno", coordinate: CLLocationCoordinate2D(latitude: 50.2052, longitude: 19.275)),
        City(id: "slupsk", name: "Słupsk", coordinate: CLLocationCoordinate2D(latitude: 54.4641, longitude: 17.0287)),
        City(id: "jastrzebie", name: "Jastrzębie-Zdrój", coordinate: CLLocationCoordinate2D(latitude: 49.9536, longitude: 18.5878)),
        City(id: "nowysacz", name: "Nowy Sącz", coordinate: CLLocationCoordinate2D(latitude: 49.6253, longitude: 20.6974)),
        City(id: "inowroclaw", name: "Inowrocław", coordinate: CLLocationCoordinate2D(latitude: 52.7989, longitude: 18.2639)),
        City(id: "lubin", name: "Lubin", coordinate: CLLocationCoordinate2D(latitude: 51.3984, longitude: 16.2017)),
        City(id: "ostrowiec", name: "Ostrowiec Świętokrzyski", coordinate: CLLocationCoordinate2D(latitude: 50.9298, longitude: 21.3853)),
        City(id: "suwalki", name: "Suwałki", coordinate: CLLocationCoordinate2D(latitude: 54.099, longitude: 22.9252)),
        City(id: "stargard", name: "Stargard", coordinate: CLLocationCoordinate2D(latitude: 53.3377, longitude: 15.045)),
        City(id: "gniezno", name: "Gniezno", coordinate: CLLocationCoordinate2D(latitude: 52.5348, longitude: 17.5826)),
        City(id: "ostrow", name: "Ostrów Wielkopolski", coordinate: CLLocationCoordinate2D(latitude: 51.655, longitude: 17.8068)),
        City(id: "piotrkow", name: "Piotrków Trybunalski", coordinate: CLLocationCoordinate2D(latitude: 51.4052, longitude: 19.7032)),
        City(id: "pabianice", name: "Pabianice", coordinate: CLLocationCoordinate2D(latitude: 51.6635, longitude: 19.3562)),
        City(id: "zamosc", name: "Zamość", coordinate: CLLocationCoordinate2D(latitude: 50.7231, longitude: 23.2519)),
        City(id: "lomza", name: "Łomża", coordinate: CLLocationCoordinate2D(latitude: 53.1781, longitude: 22.0594)),
        City(id: "chelm", name: "Chełm", coordinate: CLLocationCoordinate2D(latitude: 51.143, longitude: 23.4716)),
        City(id: "tomaszow", name: "Tomaszów Mazowiecki", coordinate: CLLocationCoordinate2D(latitude: 51.5313, longitude: 20.0084)),
        City(id: "zgierz", name: "Zgierz", coordinate: CLLocationCoordinate2D(latitude: 51.8564, longitude: 19.4061)),
        City(id: "mielec", name: "Mielec", coordinate: CLLocationCoordinate2D(latitude: 50.2871, longitude: 21.4241)),
        City(id: "stalowawola", name: "Stalowa Wola", coordinate: CLLocationCoordinate2D(latitude: 50.5828, longitude: 22.0534)),
        City(id: "tczew", name: "Tczew", coordinate: CLLocationCoordinate2D(latitude: 54.0924, longitude: 18.7905)),
        City(id: "belchatow", name: "Bełchatów", coordinate: CLLocationCoordinate2D(latitude: 51.3688, longitude: 19.3697)),
        City(id: "swidnica", name: "Świdnica", coordinate: CLLocationCoordinate2D(latitude: 50.8438, longitude: 16.4886)),
        City(id: "bedzin", name: "Będzin", coordinate: CLLocationCoordinate2D(latitude: 50.3259, longitude: 19.1278)),
        City(id: "zgora", name: "Zgierz i okolice", coordinate: CLLocationCoordinate2D(latitude: 51.8564, longitude: 19.4061)),
        City(id: "starachowice", name: "Starachowice", coordinate: CLLocationCoordinate2D(latitude: 51.0526, longitude: 21.0708)),
        City(id: "tarnobrzeg", name: "Tarnobrzeg", coordinate: CLLocationCoordinate2D(latitude: 50.5744, longitude: 21.6791)),
        City(id: "pulawy", name: "Puławy", coordinate: CLLocationCoordinate2D(latitude: 51.4166, longitude: 21.9694)),
        City(id: "siedlce", name: "Siedlce", coordinate: CLLocationCoordinate2D(latitude: 52.1677, longitude: 22.2901)),
        City(id: "ostroleka", name: "Ostrołęka", coordinate: CLLocationCoordinate2D(latitude: 53.0844, longitude: 21.5724)),
        City(id: "skierniewice", name: "Skierniewice", coordinate: CLLocationCoordinate2D(latitude: 51.9566, longitude: 20.1431)),
        City(id: "starogard", name: "Starogard Gdański", coordinate: CLLocationCoordinate2D(latitude: 53.9634, longitude: 18.5284)),
        City(id: "krosno", name: "Krosno", coordinate: CLLocationCoordinate2D(latitude: 49.6887, longitude: 21.7706)),
        City(id: "kolobrzeg", name: "Kołobrzeg", coordinate: CLLocationCoordinate2D(latitude: 54.1759, longitude: 15.5833)),
        City(id: "myszkow", name: "Myszków", coordinate: CLLocationCoordinate2D(latitude: 50.5756, longitude: 19.3242)),
        City(id: "zywiec", name: "Żywiec", coordinate: CLLocationCoordinate2D(latitude: 49.6865, longitude: 19.1945)),
        City(id: "kutno", name: "Kutno", coordinate: CLLocationCoordinate2D(latitude: 52.233, longitude: 19.3608))
    ]

    private static let byID: [String: City] = Dictionary(uniqueKeysWithValues: allCities.map { ($0.id, $0) })

    /// Looks up a city in the catalog by exact id, returning `nil` if not found.
    static func city(id: String) -> City? {
        byID[id]
    }
}
