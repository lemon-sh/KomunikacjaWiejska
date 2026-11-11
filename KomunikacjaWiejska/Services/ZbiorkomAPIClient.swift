import Foundation
import os

/// Native `URLSession` actor client targeting `https://api.zbiorkom.live/api6` (REST + SSE).

nonisolated enum ZbiorkomAPIError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidParameter(String)
    case httpError(statusCode: Int)
    case invalidResponse
    case decodingError(String)
    case transport(URLError.Code)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL, .invalidParameter:
            return String(localized: "error.invalidURL")
        case let .httpError(statusCode):
            return String(format: String(localized: "error.http"), statusCode)
        case .invalidResponse:
            return String(localized: "error.invalidResponse")
        case .decodingError:
            return String(localized: "error.decoding")
        case let .transport(code):
            switch code {
            case .notConnectedToInternet:
                return String(localized: "error.offline")
            case .timedOut:
                return String(localized: "error.timeout")
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return String(localized: "error.cannotConnect")
            default:
                return String(localized: "error.network")
            }
        case let .serverError(code):
            return String(format: String(localized: "error.server"), code)
        }
    }
}

actor ZbiorkomAPIClient: TransitDataProviding {
    static let shared = ZbiorkomAPIClient()

    private static let baseURL = URL(string: "https://api.zbiorkom.live/api6")
    private static let requestTimeout: TimeInterval = 15
    private static let maxTransientRetries = 1

    /// Matches JavaScript `encodeURIComponent` strictly so `:` and `/` in IDs (`3:MM831`) are encoded.
    private static let pathSegmentAllowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let maxSSEReconnectAttempts: Int
    private let sseReconnectDelay: Duration
    private let reconnectOnCleanEOF: Bool

    init(
        session: URLSession? = nil,
        maxSSEReconnectAttempts: Int = MapConstants.sseMaxReconnectAttempts,
        sseReconnectDelay: Duration = MapConstants.sseReconnectDelay,
        reconnectOnCleanEOF: Bool = true
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = 60 * 60
            self.session = URLSession(configuration: configuration)
        }
        self.decoder = JSONDecoder()
        self.maxSSEReconnectAttempts = maxSSEReconnectAttempts
        self.sseReconnectDelay = sseReconnectDelay
        self.reconnectOnCleanEOF = reconnectOnCleanEOF
    }

    // MARK: - REST Endpoints

    func fetchCities() async throws -> [City] {
        guard let url = Self.baseURL else {
            throw ZbiorkomAPIError.invalidURL
        }
        Logger.api.debug("Fetching dynamic cities catalog from /api6")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await performRequest(request)
        do {
            let response = try decoder.decode(CitiesResponse.self, from: data)
            return response.cities
        } catch {
            Logger.api.error("Failed decoding /api6 cities response: \(error.localizedDescription, privacy: .public)")
            throw ZbiorkomAPIError.decodingError(error.localizedDescription)
        }
    }

    func fetchVehicleMetadata(city: String, vehicleId: String) async throws -> VehicleMetadata {
        let encodedCity = try Self.encodeSegment(city, name: "city")
        let encodedVehicle = try Self.encodeSegment(vehicleId, name: "vehicleId")
        let url = try Self.makeEndpointURL(encodedSegments: [encodedCity, "vehicles", "vehicle", encodedVehicle])

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await performRequest(request)
        do {
            return try decoder.decode(VehicleMetadata.self, from: data)
        } catch {
            Logger.api.error("Failed decoding vehicle metadata: \(error.localizedDescription, privacy: .public)")
            throw ZbiorkomAPIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - SSE Streams

    nonisolated func streamMapFeatures(
        city: String,
        zoom: Double,
        bbox: BoundingBox
    ) -> AsyncThrowingStream<MapFeaturesEvent, Error> {
        makeSSEStream { [decoder] in
            let url = try Self.mapFeaturesURL(city: city, zoom: zoom, bbox: bbox)
            return (url, { sseEvent in
                switch sseEvent.event {
                case "initial":
                    let payload = try decoder.decode(MapFeaturesInitial.self, from: sseEvent.data)
                    return .initial(payload)
                case "message":
                    let payload = try decoder.decode(MapFeaturesUpdate.self, from: sseEvent.data)
                    return .message(payload)
                case "errorCode":
                    let message = String(data: sseEvent.data, encoding: .utf8) ?? "errorCode"
                    throw ZbiorkomAPIError.serverError(message)
                default:
                    return nil
                }
            })
        }
    }

    nonisolated func streamStopDepartures(
        city: String,
        stopId: String,
        limit: Int = MapConstants.defaultStopDeparturesLimit
    ) -> AsyncThrowingStream<StopStreamEvent, Error> {
        makeSSEStream { [decoder] in
            let url = try Self.stopStreamURL(city: city, stopId: stopId, limit: limit)
            return (url, { sseEvent in
                switch sseEvent.event {
                case "initial":
                    let stop = try decoder.decode(Stop.self, from: sseEvent.data)
                    return .initial(stop)
                case "message":
                    let departures = try decoder.decode([StopDeparture].self, from: sseEvent.data)
                    return .message(departures)
                case "errorCode":
                    let message = String(data: sseEvent.data, encoding: .utf8) ?? "errorCode"
                    throw ZbiorkomAPIError.serverError(message)
                default:
                    return nil
                }
            })
        }
    }

    nonisolated func streamVehiclePosition(
        city: String,
        vehicleId: String
    ) -> AsyncThrowingStream<TripStreamEvent, Error> {
        makeSSEStream { [decoder] in
            let url = try Self.vehicleStreamURL(city: city, vehicleId: vehicleId)
            return (url, { sseEvent in
                try Self.decodeTripStreamEvent(sseEvent, decoder: decoder)
            })
        }
    }

    nonisolated func streamTrip(
        city: String,
        tripId: String
    ) -> AsyncThrowingStream<TripStreamEvent, Error> {
        makeSSEStream { [decoder] in
            let url = try Self.tripStreamURL(city: city, tripId: tripId)
            return (url, { sseEvent in
                try Self.decodeTripStreamEvent(sseEvent, decoder: decoder)
            })
        }
    }

    // MARK: - URL Builders

    private static func mapFeaturesURL(city: String, zoom: Double, bbox: BoundingBox) throws -> URL {
        let encodedCity = try encodeSegment(city, name: "city")
        let formattedZoom: String
        if zoom.truncatingRemainder(dividingBy: 1.0) == 0 {
            formattedZoom = String(Int(zoom))
        } else {
            formattedZoom = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), zoom)
        }
        return try makeEndpointURL(encodedSegments: [encodedCity, "mapFeatures", formattedZoom, bbox.queryValue, "stream"])
    }

    private static func stopStreamURL(city: String, stopId: String, limit: Int) throws -> URL {
        let encodedCity = try encodeSegment(city, name: "city")
        let encodedStop = try encodeSegment(stopId, name: "stopId")
        return try makeEndpointURL(
            encodedSegments: [encodedCity, "stops", encodedStop, "stream"],
            queryItems: [URLQueryItem(name: "limit", value: String(max(1, limit)))]
        )
    }

    private static func vehicleStreamURL(city: String, vehicleId: String) throws -> URL {
        let encodedCity = try encodeSegment(city, name: "city")
        let encodedVehicle = try encodeSegment(vehicleId, name: "vehicleId")
        return try makeEndpointURL(encodedSegments: [encodedCity, "positions", encodedVehicle, "stream"])
    }

    private static func tripStreamURL(city: String, tripId: String) throws -> URL {
        let encodedCity = try encodeSegment(city, name: "city")
        let encodedTrip = try encodeSegment(tripId, name: "tripId")
        return try makeEndpointURL(encodedSegments: [encodedCity, "trips", encodedTrip, "stream"])
    }

    private static func makeEndpointURL(
        encodedSegments: [String],
        queryItems: [URLQueryItem]? = nil
    ) throws -> URL {
        guard let baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ZbiorkomAPIError.invalidURL
        }
        components.percentEncodedPath = "\(baseURL.path)/\(encodedSegments.joined(separator: "/"))"
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ZbiorkomAPIError.invalidURL
        }
        return url
    }

    private static func encodeSegment(_ raw: String, name: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowedCharacters) else {
            throw ZbiorkomAPIError.invalidParameter(name)
        }
        return encoded
    }

    private static func decodeTripStreamEvent(_ sseEvent: SSEEvent, decoder: JSONDecoder) throws -> TripStreamEvent? {
        switch sseEvent.event {
        case "initial":
            let payload = try decoder.decode(TripInitial.self, from: sseEvent.data)
            return .initial(payload)
        case "message":
            let payload = try decoder.decode(TripUpdate.self, from: sseEvent.data)
            return .message(payload)
        case "errorCode":
            let message = String(data: sseEvent.data, encoding: .utf8) ?? "errorCode"
            throw ZbiorkomAPIError.serverError(message)
        default:
            return nil
        }
    }

    // MARK: - Internal Transport

    private nonisolated func makeSSEStream<Event: Sendable>(
        build: @escaping @Sendable () throws -> (URL, @Sendable (SSEEvent) throws -> Event?)
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let workerTask = Task {
                do {
                    let (url, parseEvent) = try build()
                    try await self.consumeSSE(url: url, parseEvent: parseEvent, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                workerTask.cancel()
            }
        }
    }

    private func consumeSSE<Event: Sendable>(
        url: URL,
        parseEvent: @Sendable (SSEEvent) throws -> Event?,
        continuation: AsyncThrowingStream<Event, Error>.Continuation
    ) async throws {
        var attempt = 0

        while !Task.isCancelled {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            var suggestedRetryDelay: Duration?

            do {
                let (bytes, response) = try await session.bytes(for: request)
                try Self.validateHTTPResponse(response)

                var parser = SSEFrameParser()
                var receivedAnyEventInAttempt = false

                for try await byte in bytes {
                    try Task.checkCancellation()
                    if let sseEvent = parser.append(byte: byte) {
                        receivedAnyEventInAttempt = true
                        attempt = 0
                        if let retryMs = sseEvent.retryMs {
                            suggestedRetryDelay = .milliseconds(retryMs)
                        }
                        if let parsed = try parseEvent(sseEvent) {
                            continuation.yield(parsed)
                        }
                    }
                }

                if let trailing = parser.finishStream() {
                    receivedAnyEventInAttempt = true
                    attempt = 0
                    if let parsed = try parseEvent(trailing) {
                        continuation.yield(parsed)
                    }
                }

                if receivedAnyEventInAttempt {
                    if !reconnectOnCleanEOF {
                        return
                    }
                    // Browser EventSource always reconnects after server/proxy EOF while active.
                } else {
                    throw ZbiorkomAPIError.invalidResponse
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ZbiorkomAPIError {
                switch error {
                case .invalidURL, .invalidParameter, .decodingError, .serverError:
                    throw error
                case let .httpError(statusCode) where !(500...599).contains(statusCode) && statusCode != 429:
                    throw error
                default:
                    if attempt >= maxSSEReconnectAttempts {
                        throw error
                    }
                }
            } catch let urlError as URLError {
                if attempt >= maxSSEReconnectAttempts {
                    throw ZbiorkomAPIError.transport(urlError.code)
                }
            } catch {
                if error is DecodingError {
                    throw ZbiorkomAPIError.decodingError(error.localizedDescription)
                }
                if attempt >= maxSSEReconnectAttempts {
                    throw ZbiorkomAPIError.invalidResponse
                }
            }

            attempt += 1
            let delay = suggestedRetryDelay ?? sseReconnectDelay
            Logger.api.debug("Reconnecting SSE stream (attempt \(attempt)/\(self.maxSSEReconnectAttempts)): \(url.absoluteString, privacy: .public)")
            try await Task.sleep(for: delay)
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        var lastError: Error?

        for attempt in 0...Self.maxTransientRetries {
            if attempt > 0 {
                Logger.api.debug("Retrying request attempt \(attempt + 1): \(request.url?.absoluteString ?? "", privacy: .public)")
                try await Task.sleep(for: .milliseconds(300))
            }

            do {
                let (data, response) = try await session.data(for: request)
                try Self.validateHTTPResponse(response)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ZbiorkomAPIError {
                if case let .httpError(code) = error, (500...599).contains(code), attempt < Self.maxTransientRetries {
                    lastError = error
                    continue
                }
                throw error
            } catch let urlError as URLError {
                if Self.isTransientURLError(urlError), attempt < Self.maxTransientRetries {
                    lastError = urlError
                    continue
                }
                throw ZbiorkomAPIError.transport(urlError.code)
            } catch {
                throw error
            }
        }

        if let apiError = lastError as? ZbiorkomAPIError {
            throw apiError
        }
        if let urlError = lastError as? URLError {
            throw ZbiorkomAPIError.transport(urlError.code)
        }
        throw ZbiorkomAPIError.invalidResponse
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZbiorkomAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            Logger.api.error("HTTP \(httpResponse.statusCode) from \(httpResponse.url?.absoluteString ?? "", privacy: .public)")
            throw ZbiorkomAPIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private static func isTransientURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
}
