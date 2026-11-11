import Foundation
import os
@testable import KomunikacjaWiejska

/// Hermetic `TransitDataProviding` stub for `MapViewModel` and UI tests.

nonisolated final class StubStopsProvider: TransitDataProviding, @unchecked Sendable {
    struct MapRequest: Equatable, Sendable {
        let city: String
        let zoom: Double
        let bbox: BoundingBox
    }

    struct StopRequest: Equatable, Sendable {
        let city: String
        let stopId: String
        let limit: Int
    }

    struct VehicleRequest: Equatable, Sendable {
        let city: String
        let vehicleId: String
    }

    struct TripRequest: Equatable, Sendable {
        let city: String
        let tripId: String
    }

    private struct State: Sendable {
        var mapRequests: [MapRequest] = []
        var stopRequests: [StopRequest] = []
        var vehicleRequests: [VehicleRequest] = []
        var tripRequests: [TripRequest] = []
        var metadataRequests: [VehicleRequest] = []
        var citiesFetchCount: Int = 0
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    var citiesHandler: @Sendable () async throws -> [City]
    var mapStreamHandler: @Sendable (String, Double, BoundingBox) -> AsyncThrowingStream<MapFeaturesEvent, Error>
    var stopStreamHandler: @Sendable (String, String, Int) -> AsyncThrowingStream<StopStreamEvent, Error>
    var vehicleStreamHandler: @Sendable (String, String) -> AsyncThrowingStream<TripStreamEvent, Error>
    var tripStreamHandler: @Sendable (String, String) -> AsyncThrowingStream<TripStreamEvent, Error>
    var vehicleMetadataHandler: @Sendable (String, String) async throws -> VehicleMetadata

    init(
        citiesHandler: @escaping @Sendable () async throws -> [City] = { StubStopsProvider.sampleCities },
        mapStreamHandler: @escaping @Sendable (String, Double, BoundingBox) -> AsyncThrowingStream<MapFeaturesEvent, Error> = { _, _, _ in
            AsyncThrowingStream { $0.finish() }
        },
        stopStreamHandler: @escaping @Sendable (String, String, Int) -> AsyncThrowingStream<StopStreamEvent, Error> = { _, _, _ in
            AsyncThrowingStream { $0.finish() }
        },
        vehicleStreamHandler: @escaping @Sendable (String, String) -> AsyncThrowingStream<TripStreamEvent, Error> = { _, _ in
            AsyncThrowingStream { $0.finish() }
        },
        tripStreamHandler: @escaping @Sendable (String, String) -> AsyncThrowingStream<TripStreamEvent, Error> = { _, _ in
            AsyncThrowingStream { $0.finish() }
        },
        vehicleMetadataHandler: @escaping @Sendable (String, String) async throws -> VehicleMetadata = { _, id in
            VehicleMetadata(id: id)
        }
    ) {
        self.citiesHandler = citiesHandler
        self.mapStreamHandler = mapStreamHandler
        self.stopStreamHandler = stopStreamHandler
        self.vehicleStreamHandler = vehicleStreamHandler
        self.tripStreamHandler = tripStreamHandler
        self.vehicleMetadataHandler = vehicleMetadataHandler
    }

    /// Convenience builder emitting static `[MapFeaturesEvent]` sequences in order.
    convenience init(
        cities: [City] = StubStopsProvider.sampleCities,
        mapEventsHandler: @escaping @Sendable (String, Double, BoundingBox) async throws -> [MapFeaturesEvent]
    ) {
        self.init(
            citiesHandler: { cities },
            mapStreamHandler: { city, zoom, bbox in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            for event in try await mapEventsHandler(city, zoom, bbox) {
                                continuation.yield(event)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }

    var requestedMapRequests: [MapRequest] {
        stateLock.withLock { $0.mapRequests }
    }

    var requestedStopRequests: [StopRequest] {
        stateLock.withLock { $0.stopRequests }
    }

    var requestedVehicleRequests: [VehicleRequest] {
        stateLock.withLock { $0.vehicleRequests }
    }

    var requestedTripRequests: [TripRequest] {
        stateLock.withLock { $0.tripRequests }
    }

    var requestedMetadataRequests: [VehicleRequest] {
        stateLock.withLock { $0.metadataRequests }
    }

    var citiesFetchCount: Int {
        stateLock.withLock { $0.citiesFetchCount }
    }

    func fetchCities() async throws -> [City] {
        stateLock.withLock { $0.citiesFetchCount += 1 }
        return try await citiesHandler()
    }

    func streamMapFeatures(
        city: String,
        zoom: Double,
        bbox: BoundingBox
    ) -> AsyncThrowingStream<MapFeaturesEvent, Error> {
        stateLock.withLock {
            $0.mapRequests.append(MapRequest(city: city, zoom: zoom, bbox: bbox))
        }
        return mapStreamHandler(city, zoom, bbox)
    }

    func streamStopDepartures(
        city: String,
        stopId: String,
        limit: Int
    ) -> AsyncThrowingStream<StopStreamEvent, Error> {
        stateLock.withLock {
            $0.stopRequests.append(StopRequest(city: city, stopId: stopId, limit: limit))
        }
        return stopStreamHandler(city, stopId, limit)
    }

    func streamVehiclePosition(
        city: String,
        vehicleId: String
    ) -> AsyncThrowingStream<TripStreamEvent, Error> {
        stateLock.withLock {
            $0.vehicleRequests.append(VehicleRequest(city: city, vehicleId: vehicleId))
        }
        return vehicleStreamHandler(city, vehicleId)
    }

    func streamTrip(
        city: String,
        tripId: String
    ) -> AsyncThrowingStream<TripStreamEvent, Error> {
        stateLock.withLock {
            $0.tripRequests.append(TripRequest(city: city, tripId: tripId))
        }
        return tripStreamHandler(city, tripId)
    }

    func fetchVehicleMetadata(city: String, vehicleId: String) async throws -> VehicleMetadata {
        stateLock.withLock {
            $0.metadataRequests.append(VehicleRequest(city: city, vehicleId: vehicleId))
        }
        return try await vehicleMetadataHandler(city, vehicleId)
    }

    // MARK: - Test Fixtures

    static let sampleWarsaw = City(
        id: "warsaw",
        name: "Warszawa",
        latitude: 52.2297,
        longitude: 21.0122,
        description: "WTP",
        category: "poland",
        coverageRadiusMeters: 50_000,
        aliases: ["warsaw", "wtp"]
    )

    static let sampleKrakow = City(
        id: "krakow",
        name: "Kraków",
        latitude: 50.06865,
        longitude: 19.94781,
        description: "ZTP",
        category: "poland",
        coverageRadiusMeters: 40_000,
        aliases: ["krakow", "mpk"]
    )

    static let samplePoznan = City(
        id: "poznan",
        name: "Poznań",
        latitude: 52.40777,
        longitude: 16.91249,
        description: "ZTM",
        category: "poland",
        coverageRadiusMeters: 40_000,
        aliases: ["poznan"]
    )

    static let sampleTricity = City(
        id: "tricity",
        name: "Trójmiasto",
        latitude: 54.35188,
        longitude: 18.64631,
        description: "Gdańsk, Gdynia, Sopot",
        category: "poland",
        coverageRadiusMeters: 45_000,
        aliases: ["gdansk", "gdynia"]
    )

    static let sampleLodz = City(
        id: "lodz",
        name: "Łódź",
        latitude: 51.77025,
        longitude: 19.46563,
        description: "MPK",
        category: "poland",
        coverageRadiusMeters: 40_000,
        aliases: ["lodz"]
    )

    static let samplePKP = City(
        id: "pkp",
        name: "PKP",
        latitude: 52.255633,
        longitude: 21.035699,
        isVirtual: true,
        coverageRadiusMeters: 0,
        aliases: ["pkp", "kolej"]
    )

    static let sampleMLD = City(
        id: "mld",
        name: "Małopolskie Linie Dowozowe",
        latitude: 50.067745,
        longitude: 19.949332,
        isVirtual: true,
        coverageRadiusMeters: 0,
        aliases: ["mld"]
    )

    static let sampleCities: [City] = [
        sampleWarsaw,
        sampleKrakow,
        samplePoznan,
        sampleTricity,
        sampleLodz,
        samplePKP,
        sampleMLD
    ]

    static func sampleStop(
        id: String = "s1",
        city: String = "warsaw",
        name: String = "Centrum",
        code: String = "01",
        lon: Double = 21.0122,
        lat: Double = 52.2297,
        vehicleTypes: [RouteType] = [.bus],
        bearing: Double? = nil,
        direction: String = "",
        routes: [StopRoute] = [],
        entrances: [StopEntrance] = [],
        hasFullMetadata: Bool = false
    ) -> Stop {
        Stop(
            id: id,
            city: city,
            name: name,
            code: code,
            latitude: lat,
            longitude: lon,
            vehicleTypes: vehicleTypes,
            bearing: bearing,
            direction: direction,
            routes: routes,
            entrances: entrances,
            hasFullMetadata: hasFullMetadata
        )
    }

    static func sampleRoute(
        id: String = "520",
        city: String = "warsaw",
        name: String = "520",
        longName: String = "Płocka-Szpital — Marysin",
        agency: String = "default",
        type: RouteType = .bus,
        color: String = "#97160f"
    ) -> StopRoute {
        StopRoute(
            id: id,
            city: city,
            name: name,
            longName: longName,
            agency: agency,
            type: type,
            color: color
        )
    }

    static func sampleVehicle(
        id: String = "v1",
        city: String = "warsaw",
        routeName: String = "175",
        routeType: RouteType = .bus,
        color: String = "#97160f",
        brigade: String? = "1",
        lon: Double = 21.0122,
        lat: Double = 52.2297,
        bearing: Double? = 90,
        lastPingMs: Int64? = 1_794_432_450_000,
        tripId: String? = "trip-1",
        percentTraveled: Double? = 42.0
    ) -> VehiclePosition {
        VehiclePosition(
            id: id,
            city: city,
            route: StopRoute(
                id: routeName,
                city: city,
                name: routeName,
                longName: "Centrum — Lotnisko Chopina",
                agency: "default",
                type: routeType,
                color: color
            ),
            brigade: brigade,
            latitude: lat,
            longitude: lon,
            bearing: bearing,
            lastPingMs: lastPingMs,
            tripId: tripId,
            percentTraveled: percentTraveled
        )
    }

    static func sampleDot(
        id: String = "dot-0",
        colorHex: String = "#296d00",
        lon: Double = 21.0122,
        lat: Double = 52.2297
    ) -> DotVehicle {
        DotVehicle(id: id, colorHex: colorHex, latitude: lat, longitude: lon)
    }
}
