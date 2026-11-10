import Foundation
import os

enum ZbiorkomAPIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    /// The server answered with something that is not an `HTTPURLResponse`.
    case invalidResponse
    case transport(URLError.Code)
    case serverError(String)
    case httpError(statusCode: Int)
    /// Associated value carries DEBUG-only decoding diagnostics. The
    /// user-facing message stays short and localized.
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalidURL")
        case .invalidResponse:
            return String(localized: "error.invalidResponse")
        case .transport(let code):
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
        case .serverError(let code):
            return String(format: String(localized: "error.server"), code)
        case .httpError(let statusCode):
            return String(format: String(localized: "error.http"), statusCode)
        case .decodingError:
            return String(localized: "error.decoding")
        }
    }
}

actor ZbiorkomAPIClient {
    static let shared = ZbiorkomAPIClient()

    /// Built defensively with a failable initializer; if this fails the client throws `.invalidURL`.
    private static let baseURL = URL(string: "https://api.zbiorkom.live/api6-open")
    /// Requests are bounded to 15 s; MapViewModel additionally cancels in-flight work when the viewport changes.
    private static let requestTimeout: TimeInterval = 15
    /// One retry with jitter for transient transport failures and 5xx responses. 4xx and offline are never retried.
    private static let maxRetryCount = 1
    /// Reusable JSON decoder isolated to the actor.
    private static let decoder = JSONDecoder()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchStops(city: String, bbox: BoundingBox? = nil) async throws -> [Stop] {
        guard let baseURL = Self.baseURL else {
            throw ZbiorkomAPIError.invalidURL
        }
        let stopsURL = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("stops")

        var components = URLComponents(url: stopsURL, resolvingAgainstBaseURL: false)
        if let bbox = bbox {
            components?.queryItems = [
                URLQueryItem(name: "bbox", value: bbox.queryValue)
            ]
        }
        guard let url = components?.url else {
            throw ZbiorkomAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Logger.api.debug("Fetching stops for city: \(city, privacy: .public), bbox: \(bbox?.queryValue ?? "none", privacy: .public)")

        let data = try await perform(request)

        do {
            let decoded = try Self.decoder.decode(StopsResponse.self, from: data)
            Logger.api.debug("Successfully decoded \(decoded.stops.count, privacy: .public) stops for city: \(city, privacy: .public)")
            return decoded.stops
        } catch {
            let details: String
            #if DEBUG
            details = String(reflecting: error)
            Logger.api.error("Stops decoding failed: \(details, privacy: .public)")
            #else
            details = ""
            Logger.api.error("Stops decoding failed")
            #endif
            throw ZbiorkomAPIError.decodingError(details)
        }
    }

    func fetchVehicles(city: String, bbox: BoundingBox) async throws -> [VehiclePosition] {
        guard let baseURL = Self.baseURL else {
            throw ZbiorkomAPIError.invalidURL
        }
        let positionsURL = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("positions")
            .appendingPathComponent(bbox.queryValue)

        var request = URLRequest(url: positionsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Logger.api.debug("Fetching vehicles for city: \(city, privacy: .public), bbox: \(bbox.queryValue, privacy: .public)")

        let data = try await perform(request)

        do {
            let decoded = try Self.decoder.decode(VehiclesResponse.self, from: data)
            Logger.api.debug("Successfully decoded \(decoded.positions.count, privacy: .public) vehicles for city: \(city, privacy: .public)")
            return decoded.positions
        } catch {
            let details: String
            #if DEBUG
            details = String(reflecting: error)
            Logger.api.error("Vehicles decoding failed: \(details, privacy: .public)")
            #else
            details = ""
            Logger.api.error("Vehicles decoding failed")
            #endif
            throw ZbiorkomAPIError.decodingError(details)
        }
    }

    /// Performs the request with a bounded retry policy (2P5-1).
    private func perform(_ request: URLRequest) async throws -> Data {
        for attempt in 0...Self.maxRetryCount {
            try Task.checkCancellation()
            Logger.api.debug("Starting request [attempt \(attempt + 1, privacy: .public)]: \(request.url?.absoluteString ?? "", privacy: .public)")

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ZbiorkomAPIError.invalidResponse
                }

                Logger.api.debug("Received response [HTTP \(httpResponse.statusCode, privacy: .public)] for \(request.url?.absoluteString ?? "", privacy: .public) (\(data.count, privacy: .public) bytes)")

                if (500...599).contains(httpResponse.statusCode), attempt < Self.maxRetryCount {
                    Logger.api.debug("Server error \(httpResponse.statusCode, privacy: .public), retrying with backoff...")
                    try await Self.backoff()
                    continue
                }

                guard httpResponse.statusCode == 200 else {
                    if let errorPayload = try? Self.decoder.decode([String: String].self, from: data),
                       let errorCode = errorPayload["error"] {
                        throw ZbiorkomAPIError.serverError(errorCode)
                    }
                    throw ZbiorkomAPIError.httpError(statusCode: httpResponse.statusCode)
                }

                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch let urlError as URLError {
                Logger.api.error("Transport error \(urlError.code.rawValue, privacy: .public) for \(request.url?.absoluteString ?? "", privacy: .public)")
                guard Self.isTransient(urlError.code), attempt < Self.maxRetryCount else {
                    throw ZbiorkomAPIError.transport(urlError.code)
                }
                Logger.api.debug("Transient transport error, retrying with backoff...")
                try await Self.backoff()
            }
        }
        throw ZbiorkomAPIError.transport(.timedOut)
    }

    /// Determines whether an error is transient and recoverable.
    /// Note: `.notConnectedToInternet` is intentionally excluded; failing fast on offline avoids a pointless retry delay.
    private static func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost:
            return true
        case .notConnectedToInternet:
            return false
        default:
            return false
        }
    }

    /// Randomized backoff so parallel clients do not retry in lockstep.
    private static func backoff() async throws {
        let milliseconds = Int.random(in: 200...600)
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}
