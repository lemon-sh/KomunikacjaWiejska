import Foundation
@testable import KomunikacjaWiejska
import Testing

/// Serialized because `MockURLProtocol.handler` is process-wide state.
@Suite("ZbiorkomAPIClient", .serialized)
@MainActor
struct ZbiorkomAPIClientTests {
    private func makeClient() -> ZbiorkomAPIClient {
        ZbiorkomAPIClient(session: MockURLProtocol.makeSession(), retryBackoff: {})
    }

    @Test("Decodes a 200 response")
    func decodesSuccess() async throws {
        MockURLProtocol.handler = { _ in
            try (StubResponses.http(), StubResponses.validStopsJSON)
        }
        defer { MockURLProtocol.handler = nil }

        let stops = try await makeClient().fetchStops(city: "rybnik", bbox: nil)
        #expect(stops.count == 1)
        #expect(stops.first?.id == "rybnik-srodmiescie-dworek261-0-j58h8")
    }

    @Test("Sends the bbox query parameter and Accept header")
    func sendsBBoxAndHeaders() async throws {
        let capturedURL = LockedValue<URL?>(nil)
        let capturedAccept = LockedValue<String?>(nil)
        MockURLProtocol.handler = { request in
            capturedURL.value = request.url
            capturedAccept.value = request.value(forHTTPHeaderField: "Accept")
            return try (StubResponses.http(), StubResponses.validStopsJSON)
        }
        defer { MockURLProtocol.handler = nil }

        let bbox = BoundingBox(minLon: 21.0, minLat: 52.2, maxLon: 21.1, maxLat: 52.3)
        _ = try await makeClient().fetchStops(city: "warsaw", bbox: bbox)

        #expect(capturedURL.value?.query?.contains("bbox=") == true)
        #expect(capturedURL.value?.absoluteString.contains("21.000000,52.200000,21.100000,52.300000") == true)
        #expect(capturedAccept.value == "application/json")
    }

    @Test("Maps an error payload to serverError")
    func mapsErrorPayload() async throws {
        MockURLProtocol.handler = { _ in
            try (StubResponses.http(status: 400), Data(#"{"error":"invalid-city"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: ZbiorkomAPIError.serverError("invalid-city")) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }
    }

    @Test("Maps a non-error 4xx payload to httpError and does not retry")
    func mapsHTTPErrorWithoutRetry() async throws {
        let callCount = LockedValue<Int>(0)
        MockURLProtocol.handler = { _ in
            callCount.mutate { $0 += 1 }
            return try (StubResponses.http(status: 404), Data())
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: ZbiorkomAPIError.httpError(statusCode: 404)) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }
        #expect(callCount.value == 1)
    }

    @Test("Retries a 5xx once and succeeds")
    func retriesServerErrorOnce() async throws {
        let callCount = LockedValue<Int>(0)
        MockURLProtocol.handler = { _ in
            let attempt = callCount.value + 1
            callCount.value = attempt
            if attempt == 1 {
                return try (StubResponses.http(status: 503), Data())
            }
            return try (StubResponses.http(), StubResponses.validStopsJSON)
        }
        defer { MockURLProtocol.handler = nil }

        let stops = try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        #expect(stops.count == 1)
        #expect(callCount.value == 2)
    }

    @Test("Maps malformed JSON to decodingError")
    func mapsDecodingError() async throws {
        MockURLProtocol.handler = { _ in
            try (StubResponses.http(), Data(#"{"stops": "nope"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        do {
            _ = try await makeClient().fetchStops(city: "warsaw", bbox: nil)
            Issue.record("Expected a decoding error")
        } catch let error as ZbiorkomAPIError {
            guard case .decodingError = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("Maps a non-HTTP response to invalidResponse")
    func mapsInvalidResponse() async throws {
        MockURLProtocol.handler = { _ in
            try (StubResponses.nonHTTP(), Data())
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: ZbiorkomAPIError.invalidResponse) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }
    }

    @Test("Maps timeouts to a localized transport message")
    func mapsTimeout() async throws {
        MockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: ZbiorkomAPIError.transport(.timedOut)) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }

        // The exact copy is localized; assert it is present and distinct from
        // other transport failures rather than hard-coding one language.
        let timeoutMessage = try #require(ZbiorkomAPIError.transport(.timedOut).errorDescription)
        let offlineMessage = try #require(ZbiorkomAPIError.transport(.notConnectedToInternet).errorDescription)
        #expect(!timeoutMessage.isEmpty)
        #expect(timeoutMessage != offlineMessage)
    }

    @Test("Decoding diagnostics stay out of the user-facing message")
    func hidesDecodingDetails() throws {
        let message = try #require(
            ZbiorkomAPIError.decodingError("secret internal detail").errorDescription
        )
        #expect(!message.contains("secret internal detail"))
        #expect(!message.isEmpty)
    }

    @Test("Does not retry when offline")
    func doesNotRetryOffline() async throws {
        let callCount = LockedValue<Int>(0)
        MockURLProtocol.handler = { _ in
            callCount.mutate { $0 += 1 }
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: ZbiorkomAPIError.transport(.notConnectedToInternet)) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }
        #expect(callCount.value == 1)
    }

    @Test("Cancellation rethrows CancellationError directly")
    func preservesCancellation() async throws {
        MockURLProtocol.handler = { _ in
            throw URLError(.cancelled)
        }
        defer { MockURLProtocol.handler = nil }

        await #expect(throws: CancellationError.self) {
            try await makeClient().fetchStops(city: "warsaw", bbox: nil)
        }
    }

    @Test("Fetches and decodes vehicles with path-based bbox")
    func fetchVehiclesSuccess() async throws {
        let capturedURL = LockedValue<URL?>(nil)
        let sampleJSON = """
        {
            "positions": [
                {
                    "vehicle": {
                        "id": "1001",
                        "type": "3",
                        "agency": "default",
                        "model": "Solaris"
                    },
                    "routeName": "189",
                    "routeColor": "#a5248c",
                    "brigade": "1",
                    "location": [21.01, 52.23],
                    "timestamp": 1700000000000,
                    "bearing": 180,
                    "delay": 0,
                    "headsign": "Centrum",
                    "upcomingStops": [],
                    "url": "https://zbiorkom.live/sample"
                }
            ]
        }
        """.data(using: .utf8)!

        MockURLProtocol.handler = { request in
            capturedURL.value = request.url
            return try (StubResponses.http(), sampleJSON)
        }
        defer { MockURLProtocol.handler = nil }

        let bbox = BoundingBox(minLon: 21.0, minLat: 52.2, maxLon: 21.1, maxLat: 52.3)
        let vehicles = try await makeClient().fetchVehicles(city: "warsaw", bbox: bbox)

        #expect(vehicles.count == 1)
        #expect(vehicles[0].id == "default:3:1001")
        #expect(capturedURL.value?.path.contains("/api6-open/warsaw/positions/21.000000,52.200000,21.100000,52.300000") == true)
    }
}
