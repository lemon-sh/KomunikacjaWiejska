import CoreLocation
import Foundation

/// Positional models for `mapFeatures`, trips, stop departures, alerts, and vehicle metadata.

// MARK: - Map Features Stream Payloads

nonisolated struct MapFeaturesInitial: Decodable, Equatable, Sendable {
    let stops: [Stop]
    let suggestedCity: String?

    init(stops: [Stop], suggestedCity: String? = nil) {
        self.stops = stops
        self.suggestedCity = suggestedCity
    }
}

nonisolated struct MapFeaturesUpdate: Decodable, Equatable, Sendable {
    let positions: [VehiclePosition]
    let dots: [DotVehicle]
    let bbox: BoundingBox?

    private enum CodingKeys: String, CodingKey {
        case positions
        case dots
        case bbox
    }

    init(positions: [VehiclePosition], dots: [DotVehicle], bbox: BoundingBox? = nil) {
        self.positions = positions
        self.dots = dots
        self.bbox = bbox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.positions = try container.decodeIfPresent([VehiclePosition].self, forKey: .positions) ?? []
        let rawDots = try container.decodeIfPresent([RawDotTuple].self, forKey: .dots) ?? []
        self.dots = rawDots.enumerated().map { index, dot in
            DotVehicle(
                id: "dot-\(index)-\(dot.colorHex)",
                colorHex: dot.colorHex,
                latitude: dot.latitude,
                longitude: dot.longitude
            )
        }
        if container.contains(.bbox), try !container.decodeNil(forKey: .bbox) {
            let bboxDecoder = try container.superDecoder(forKey: .bbox)
            self.bbox = try BoundingBox(tupleDecoder: bboxDecoder)
        } else {
            self.bbox = nil
        }
    }
}

nonisolated enum MapFeaturesEvent: Equatable, Sendable {
    case initial(MapFeaturesInitial)
    case message(MapFeaturesUpdate)
}

// MARK: - Departures, Status & Stop Times

nonisolated enum DepartureStatus: Int, Hashable, Sendable, Decodable {
    case scheduled = 0
    case onTrip = 1
    case onPreviousTrip = 2
    case cancelled = 3

    var isLive: Bool {
        self == .onTrip || self == .onPreviousTrip
    }
}

nonisolated struct AlightOptions: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let regular = AlightOptions(rawValue: 1)
    static let forbidden = AlightOptions(rawValue: 2)
    static let onDemand = AlightOptions(rawValue: 4)
    static let isLastStop = AlightOptions(rawValue: 8)
}

/// Positional timing tuple `[scheduledMs, delayMs?, status, platform?]`.
nonisolated struct StopTimeUpdate: Hashable, Sendable, Decodable {
    let scheduledMs: Int64
    let delayMs: Int64?
    let status: DepartureStatus
    let platform: String?

    var estimatedMs: Int64 {
        scheduledMs + (delayMs ?? 0)
    }

    var scheduledDate: Date {
        Date(timeIntervalSince1970: Double(scheduledMs) / 1_000.0)
    }

    var estimatedDate: Date {
        Date(timeIntervalSince1970: Double(estimatedMs) / 1_000.0)
    }

    var isCancelled: Bool {
        status == .cancelled
    }

    var isLive: Bool {
        status.isLive
    }

    init(scheduledMs: Int64, delayMs: Int64? = nil, status: DepartureStatus = .scheduled, platform: String? = nil) {
        self.scheduledMs = scheduledMs
        self.delayMs = delayMs
        self.status = status
        self.platform = platform?.isEmpty == true ? nil : platform
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "StopTimeUpdate", minimumCount: 3)
        self.scheduledMs = try reader.decode(Int64.self, field: "scheduled")
        self.delayMs = try reader.decodeOptional(Int64.self)
        let rawStatus = try reader.decodeOptional(Int.self) ?? DepartureStatus.scheduled.rawValue
        self.status = DepartureStatus(rawValue: rawStatus) ?? .scheduled
        self.platform = try reader.decodeNonEmptyString(field: "platform")
    }
}

/// `[arrival, departure, platform?, track?, alerts?]`.
nonisolated struct TripStopUpdate: Hashable, Sendable, Decodable {
    let arrival: StopTimeUpdate
    let departure: StopTimeUpdate
    let platform: String?
    let track: String?
    let alerts: [TripAlert]

    init(
        arrival: StopTimeUpdate,
        departure: StopTimeUpdate,
        platform: String? = nil,
        track: String? = nil,
        alerts: [TripAlert] = []
    ) {
        self.arrival = arrival
        self.departure = departure
        self.platform = platform?.isEmpty == true ? nil : platform
        self.track = track?.isEmpty == true ? nil : track
        self.alerts = alerts
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "TripStopUpdate", minimumCount: 2)
        self.arrival = try reader.decode(StopTimeUpdate.self, field: "arrival")
        self.departure = try reader.decode(StopTimeUpdate.self, field: "departure")
        self.platform = try reader.decodeNonEmptyString(field: "platform")
        self.track = try reader.decodeNonEmptyString(field: "track")
        self.alerts = try reader.decodeOptional([TripAlert].self) ?? []
    }
}

// MARK: - Trip, Itinerary, Alerts & Vehicle Metadata

/// `[id, city, route, headsign, brigade?, shortName?, description?, firstStop?, lastStop?, distance?]`.
nonisolated struct TripInfo: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let city: String
    let route: StopRoute
    let headsign: String
    let brigade: String?
    let shortName: String?
    let descriptionPairs: [[String]]

    init(
        id: String,
        city: String,
        route: StopRoute,
        headsign: String,
        brigade: String? = nil,
        shortName: String? = nil,
        descriptionPairs: [[String]] = []
    ) {
        self.id = id
        self.city = city
        self.route = route
        self.headsign = headsign
        self.brigade = brigade?.isEmpty == true ? nil : brigade
        self.shortName = shortName?.isEmpty == true ? nil : shortName
        self.descriptionPairs = descriptionPairs.filter { pair in
            pair.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "TripInfo", minimumCount: 4)
        let id = try reader.decode(String.self, field: "id")
        let city = try reader.decode(String.self, field: "city")
        let route = try reader.decode(StopRoute.self, field: "route")
        let headsign = try reader.decode(String.self, field: "headsign")
        let brigade = try reader.decodeNonEmptyString(field: "brigade")
        let shortName = try reader.decodeNonEmptyString(field: "shortName")
        let descriptionPairs = try reader.decodeOptional([[String]].self) ?? []

        self.init(
            id: id,
            city: city,
            route: route,
            headsign: headsign,
            brigade: brigade,
            shortName: shortName,
            descriptionPairs: descriptionPairs
        )
    }
}

/// `[stop, alight, distance?, platform?]`.
nonisolated struct ItineraryStop: Identifiable, Hashable, Sendable, Decodable {
    let stop: Stop
    let alight: AlightOptions
    let distanceMeters: Double?
    let platform: String?

    var id: String { stop.id }
    var isBoardingForbidden: Bool { alight.contains(.forbidden) }
    var isOnDemand: Bool { alight.contains(.onDemand) }
    var isLastStop: Bool { alight.contains(.isLastStop) }

    init(stop: Stop, alight: AlightOptions = .regular, distanceMeters: Double? = nil, platform: String? = nil) {
        self.stop = stop
        self.alight = alight
        self.distanceMeters = distanceMeters
        self.platform = platform?.isEmpty == true ? nil : platform
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "ItineraryStop", minimumCount: 2)
        self.stop = try reader.decode(Stop.self, field: "stop")
        let alightRaw = try reader.decode(Int.self, field: "alight")
        self.alight = AlightOptions(rawValue: alightRaw)
        self.distanceMeters = try reader.decodeOptional(Double.self)
        self.platform = try reader.decodeNonEmptyString(field: "platform")
    }
}

/// `[stops, encodedPolyline6, ...]` returned inside trip/position `initial` SSE events.
nonisolated struct Itinerary: Equatable, Sendable, Decodable {
    let stops: [ItineraryStop]
    let encodedPolyline: String
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: Itinerary, rhs: Itinerary) -> Bool {
        lhs.stops == rhs.stops && lhs.encodedPolyline == rhs.encodedPolyline
    }

    init(stops: [ItineraryStop], encodedPolyline: String) {
        self.stops = stops
        self.encodedPolyline = encodedPolyline
        self.coordinates = PolylineDecoder.decode(encodedPolyline)
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "Itinerary", minimumCount: 2)
        let stops = try reader.decode([ItineraryStop].self, field: "stops")
        let encodedPolyline = try reader.decode(String.self, field: "shape")
        self.init(stops: stops, encodedPolyline: encodedPolyline)
    }
}

/// `[title, description, url?, publishedAt?, activeFrom?, activeUntil?, language?, detected?]`.
nonisolated struct TripAlert: Identifiable, Hashable, Sendable, Decodable {
    let title: String
    let description: String
    let url: String?
    let publishedAtMs: Int64?
    let activeFromMs: Int64?
    let activeUntilMs: Int64?
    let language: String?
    let detected: Bool

    var id: String { "\(title)-\(description)" }

    init(
        title: String,
        description: String,
        url: String? = nil,
        publishedAtMs: Int64? = nil,
        activeFromMs: Int64? = nil,
        activeUntilMs: Int64? = nil,
        language: String? = nil,
        detected: Bool = false
    ) {
        self.title = title
        self.description = description
        self.url = url?.isEmpty == true ? nil : url
        self.publishedAtMs = publishedAtMs
        self.activeFromMs = activeFromMs
        self.activeUntilMs = activeUntilMs
        self.language = language?.isEmpty == true ? nil : language
        self.detected = detected
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "TripAlert", minimumCount: 2)
        self.title = try reader.decode(String.self, field: "title")
        self.description = try reader.decode(String.self, field: "description")
        self.url = try reader.decodeNonEmptyString(field: "url")
        self.publishedAtMs = try reader.decodeOptional(Int64.self)
        self.activeFromMs = try reader.decodeOptional(Int64.self)
        self.activeUntilMs = try reader.decodeOptional(Int64.self)
        self.language = try reader.decodeNonEmptyString(field: "language")
        self.detected = try reader.decodeOptional(Bool.self) ?? false
    }
}

nonisolated struct TripInitial: Decodable, Equatable, Sendable {
    let trip: TripInfo
    let itinerary: Itinerary
}

nonisolated struct TripUpdate: Decodable, Equatable, Sendable {
    let position: VehiclePosition?
    let stops: [TripStopUpdate]
    let sequence: Int?
    let alerts: [TripAlert]?
}

nonisolated enum TripStreamEvent: Equatable, Sendable {
    case initial(TripInitial)
    case message(TripUpdate)
}

/// `[id, model, prodYear?, carrier?, imageHash?]` from `GET {city}/vehicles/vehicle/{id}`.
nonisolated struct VehicleMetadata: Equatable, Sendable, Decodable {
    let id: String
    let model: String?
    let prodYear: Int?
    let carrier: String?
    let imageHash: String?

    init(
        id: String,
        model: String? = nil,
        prodYear: Int? = nil,
        carrier: String? = nil,
        imageHash: String? = nil
    ) {
        self.id = id
        self.model = model?.isEmpty == true ? nil : model
        self.prodYear = prodYear
        self.carrier = carrier?.isEmpty == true ? nil : carrier
        self.imageHash = imageHash?.isEmpty == true ? nil : imageHash
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "VehicleMetadata", minimumCount: 1)
        let id = try reader.decode(String.self, field: "id")
        let model = try reader.decodeNonEmptyString(field: "model")
        let prodYear = try reader.decodeOptional(Int.self)
        let carrier = try reader.decodeNonEmptyString(field: "carrier")
        let imageHash = try reader.decodeNonEmptyString(field: "imageHash")
        self.init(id: id, model: model, prodYear: prodYear, carrier: carrier, imageHash: imageHash)
    }
}

// MARK: - Stop Departures Stream Payloads

/// `[trip, vehicle?, departure, destination?]`.
nonisolated struct StopDeparture: Identifiable, Hashable, Sendable, Decodable {
    let trip: TripInfo
    let vehicle: VehiclePosition?
    let departure: StopTimeUpdate
    let destination: StopTimeUpdate?

    var id: String { trip.id }

    init(
        trip: TripInfo,
        vehicle: VehiclePosition? = nil,
        departure: StopTimeUpdate,
        destination: StopTimeUpdate? = nil
    ) {
        self.trip = trip
        self.vehicle = vehicle
        self.departure = departure
        self.destination = destination
    }

    init(from decoder: Decoder) throws {
        var reader = try TupleReader(decoder: decoder, context: "StopDeparture", minimumCount: 3)
        self.trip = try reader.decode(TripInfo.self, field: "trip")
        self.vehicle = try reader.decodeOptional(VehiclePosition.self)
        self.departure = try reader.decode(StopTimeUpdate.self, field: "departure")
        self.destination = try reader.decodeOptional(StopTimeUpdate.self)
    }
}

nonisolated enum StopStreamEvent: Equatable, Sendable {
    case initial(Stop)
    case message([StopDeparture])
}
