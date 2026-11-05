import Foundation
import os

public enum ZbiorkomAPIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    /// The server answered with something that is not an `HTTPURLResponse`.
    case invalidResponse
    case transport(URLError.Code)
    case serverError(String)
    case httpError(statusCode: Int)
    /// Associated value carries DEBUG-only decoding diagnostics. The
    /// user-facing message stays short and localized.
    case decodingError(String)

    public var errorDescription: String? {
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

public actor ZbiorkomAPIClient {
    public static let shared = ZbiorkomAPIClient()

    /// Built with a failable initializer; if this ever fails the client throws
    /// `.invalidURL` instead of trapping.
    private static let baseURL = URL(string: "https://api.zbiorkom.live/api6-open")
    /// Requests are bounded to 15 s; the caller (MapViewModel) additionally
    /// cancels in-flight work when the viewport changes or the app backgrounds.
    private static let requestTimeout: TimeInterval = 15
    /// One retry with jitter for transient transport failures and 5xx
    /// responses. 4xx responses are never retried.
    private static let maxRetryCount = 1

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchStops(city: String, bbox: BoundingBox? = nil) async throws -> [Stop] {
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

        #if DEBUG
        Logger.api.debug("Fetching stops for city: \(city, privacy: .public), bbox: \(bbox?.queryValue ?? "none", privacy: .public)")
        #endif

        let data = try await perform(request)

        do {
            let decoded = try JSONDecoder().decode(StopsResponse.self, from: data)
            #if DEBUG
            Logger.api.debug("Successfully decoded \(decoded.stops.count, privacy: .public) stops for city: \(city, privacy: .public)")
            #endif
            return decoded.stops
        } catch {
            #if DEBUG
            let details = String(reflecting: error)
            Logger.api.error("Stops decoding failed: \(details, privacy: .public)")
            throw ZbiorkomAPIError.decodingError(details)
            #else
            throw ZbiorkomAPIError.decodingError("")
            #endif
        }
    }

    /// Performs the request, retrying once (with jitter) on transient failures.
    private func perform(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            #if DEBUG
            Logger.api.debug("Starting request [attempt \(attempt + 1, privacy: .public)]: \(request.url?.absoluteString ?? "", privacy: .public)")
            #endif
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ZbiorkomAPIError.invalidResponse
                }

                #if DEBUG
                Logger.api.debug("Received response [HTTP \(httpResponse.statusCode, privacy: .public)] for \(request.url?.absoluteString ?? "", privacy: .public) (\(data.count, privacy: .public) bytes)")
                #endif

                if (500...599).contains(httpResponse.statusCode), attempt < Self.maxRetryCount {
                    #if DEBUG
                    Logger.api.debug("Server error \(httpResponse.statusCode, privacy: .public), retrying with backoff...")
                    #endif
                    attempt += 1
                    try await Self.backoff()
                    continue
                }

                guard httpResponse.statusCode == 200 else {
                    if let errorPayload = try? JSONDecoder().decode([String: String].self, from: data),
                       let errorCode = errorPayload["error"] {
                        throw ZbiorkomAPIError.serverError(errorCode)
                    }
                    throw ZbiorkomAPIError.httpError(statusCode: httpResponse.statusCode)
                }

                return data
            } catch let urlError as URLError {
                #if DEBUG
                Logger.api.error("Transport error \(urlError.code.rawValue, privacy: .public) for \(request.url?.absoluteString ?? "", privacy: .public)")
                #endif
                guard Self.isTransient(urlError.code), attempt < Self.maxRetryCount, !Task.isCancelled else {
                    throw ZbiorkomAPIError.transport(urlError.code)
                }
                #if DEBUG
                Logger.api.debug("Transient transport error, retrying with backoff...")
                #endif
                attempt += 1
                try await Self.backoff()
            }
        }
    }

    private static func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
            return true
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
