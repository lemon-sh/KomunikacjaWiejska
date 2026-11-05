import CoreLocation
import Foundation

public struct City: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D
    public let defaultLatitudeDelta: Double
    public let defaultLongitudeDelta: Double

    public init(
        id: String,
        name: String,
        coordinate: CLLocationCoordinate2D,
        defaultLatitudeDelta: Double = 0.08,
        defaultLongitudeDelta: Double = 0.08
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.defaultLatitudeDelta = defaultLatitudeDelta
        self.defaultLongitudeDelta = defaultLongitudeDelta
    }

    public static func == (lhs: City, rhs: City) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static let warsaw = City(
        id: "warsaw",
        name: "Warszawa",
        coordinate: CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
    )

    public static let krakow = City(
        id: "krakow",
        name: "Kraków",
        coordinate: CLLocationCoordinate2D(latitude: 50.0647, longitude: 19.9450)
    )

    public static let wroclaw = City(
        id: "wroclaw",
        name: "Wrocław",
        coordinate: CLLocationCoordinate2D(latitude: 51.1079, longitude: 17.0385)
    )

    public static let poznan = City(
        id: "poznan",
        name: "Poznań",
        coordinate: CLLocationCoordinate2D(latitude: 52.4064, longitude: 16.9252)
    )

    public static let tricity = City(
        id: "tricity",
        name: "Trójmiasto (Gdańsk / Sopot / Gdynia)",
        coordinate: CLLocationCoordinate2D(latitude: 54.3520, longitude: 18.6466),
        defaultLatitudeDelta: 0.15,
        defaultLongitudeDelta: 0.15
    )

    public static let gzm = City(
        id: "gzm",
        name: "GZM (Katowice i Metropolia)",
        coordinate: CLLocationCoordinate2D(latitude: 50.2649, longitude: 19.0238),
        defaultLatitudeDelta: 0.15,
        defaultLongitudeDelta: 0.15
    )

    public static let lodz = City(
        id: "lodz",
        name: "Łódź",
        coordinate: CLLocationCoordinate2D(latitude: 51.7592, longitude: 19.4560)
    )

    public static let szczecin = City(
        id: "szczecin",
        name: "Szczecin",
        coordinate: CLLocationCoordinate2D(latitude: 53.4285, longitude: 14.5528)
    )

    public static let lublin = City(
        id: "lublin",
        name: "Lublin",
        coordinate: CLLocationCoordinate2D(latitude: 51.2465, longitude: 22.5684)
    )

    public static let bialystok = City(
        id: "bialystok",
        name: "Białystok",
        coordinate: CLLocationCoordinate2D(latitude: 53.1325, longitude: 23.1688)
    )

    public static let bydgoszcz = City(
        id: "bydgoszcz",
        name: "Bydgoszcz",
        coordinate: CLLocationCoordinate2D(latitude: 53.1235, longitude: 18.0084)
    )

    public static let torun = City(
        id: "torun",
        name: "Toruń",
        coordinate: CLLocationCoordinate2D(latitude: 53.0138, longitude: 18.5984)
    )

    public static let rzeszow = City(
        id: "rzeszow",
        name: "Rzeszów",
        coordinate: CLLocationCoordinate2D(latitude: 50.0412, longitude: 21.9991)
    )

    public static let kielce = City(
        id: "kielce",
        name: "Kielce",
        coordinate: CLLocationCoordinate2D(latitude: 50.8661, longitude: 20.6286)
    )

    public static let olsztyn = City(
        id: "olsztyn",
        name: "Olsztyn",
        coordinate: CLLocationCoordinate2D(latitude: 53.7784, longitude: 20.4801)
    )

    public static let opole = City(
        id: "opole",
        name: "Opole",
        coordinate: CLLocationCoordinate2D(latitude: 50.6751, longitude: 17.9213)
    )

    public static let czestochowa = City(
        id: "czestochowa",
        name: "Częstochowa",
        coordinate: CLLocationCoordinate2D(latitude: 50.8118, longitude: 19.1203)
    )

    public static let radom = City(
        id: "radom",
        name: "Radom",
        coordinate: CLLocationCoordinate2D(latitude: 51.4027, longitude: 21.1471)
    )

    public static let bielsko = City(
        id: "bielsko",
        name: "Bielsko-Biała",
        coordinate: CLLocationCoordinate2D(latitude: 49.8224, longitude: 19.0444)
    )

    public static let rybnik = City(
        id: "rybnik",
        name: "Rybnik",
        coordinate: CLLocationCoordinate2D(latitude: 50.0970, longitude: 18.5418)
    )

    public static let zielonagora = City(
        id: "zielonagora",
        name: "Zielona Góra",
        coordinate: CLLocationCoordinate2D(latitude: 51.9356, longitude: 15.5062)
    )

    public static let gorzow = City(
        id: "gorzow",
        name: "Gorzów Wielkopolski",
        coordinate: CLLocationCoordinate2D(latitude: 52.7368, longitude: 15.2288)
    )

    public static let pkp = City(
        id: "pkp",
        name: "PKP (Kolej Ogólnopolska)",
        coordinate: CLLocationCoordinate2D(latitude: 52.0693, longitude: 19.4803),
        defaultLatitudeDelta: 5.0,
        defaultLongitudeDelta: 5.0
    )

    public static let allCities: [City] = [
        .warsaw,
        .krakow,
        .wroclaw,
        .poznan,
        .tricity,
        .gzm,
        .lodz,
        .szczecin,
        .lublin,
        .bialystok,
        .bydgoszcz,
        .torun,
        .rzeszow,
        .kielce,
        .olsztyn,
        .opole,
        .czestochowa,
        .radom,
        .bielsko,
        .rybnik,
        .zielonagora,
        .gorzow,
        .pkp
    ]
}
