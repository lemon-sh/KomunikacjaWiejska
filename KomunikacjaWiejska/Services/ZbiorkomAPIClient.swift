import Foundation

public enum ZbiorkomAPIError: LocalizedError, Sendable {
    case invalidURL
    case serverError(String)
    case httpError(statusCode: Int)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Nieprawidłowy adres URL zapytania."
        case .serverError(let code):
            return "Błąd serwera: \(code)"
        case .httpError(let statusCode):
            return "Błąd HTTP (\(statusCode))."
        case .decodingError(let details):
            return "Błąd parsowania danych: \(details)"
        }
    }
}

public actor ZbiorkomAPIClient {
    public static let shared = ZbiorkomAPIClient()

    private let baseURL = URL(string: "https://api.zbiorkom.live/api6-open")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchStops(city: String, bbox: BoundingBox? = nil) async throws -> [Stop] {
        var url = baseURL.appendingPathComponent(city).appendingPathComponent("stops")

        if let bbox = bbox {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = await [
                URLQueryItem(name: "bbox", value: bbox.queryValue)
            ]
            if let queryURL = components?.url {
                url = queryURL
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZbiorkomAPIError.invalidURL
        }

        if httpResponse.statusCode != 200 {
            if let errorPayload = try? JSONDecoder().decode([String: String].self, from: data),
               let errorCode = errorPayload["error"] {
                throw ZbiorkomAPIError.serverError(errorCode)
            }
            throw ZbiorkomAPIError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(StopsResponse.self, from: data)
            return decoded.stops
        } catch {
            throw ZbiorkomAPIError.decodingError(error.localizedDescription)
        }
    }
}
