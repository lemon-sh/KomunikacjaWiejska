import Foundation
import Testing
@testable import KomunikacjaWiejska

/// Hermetic REST + SSE parser and `ZbiorkomAPIClient` tests via `MockURLProtocol`.

@Suite("Zbiorkom API Client Tests", .serialized)
struct ZbiorkomAPIClientTests {
    private func makeClient(
        reconnectAttempts: Int = 1,
        reconnectOnCleanEOF: Bool = false
    ) -> ZbiorkomAPIClient {
        ZbiorkomAPIClient(
            session: MockURLProtocol.makeSession(),
            maxSSEReconnectAttempts: reconnectAttempts,
            sseReconnectDelay: .milliseconds(10),
            reconnectOnCleanEOF: reconnectOnCleanEOF
        )
    }

    @Test("SSEFrameParser handles CRLF, comments, multi-line data, retry, and multi-byte UTF-8")
    func testSSEFrameParserFraming() {
        var parser = SSEFrameParser()
        let streamText = ": keepalive\r\nretry: 5000\r\nevent: initial\r\ndata: {\"name\":\"Kraków\"}\r\n\r\nevent: message\ndata: line1\ndata: line2\n\n"
        var events: [SSEEvent] = []
        for byte in Data(streamText.utf8) {
            if let event = parser.append(byte: byte) {
                events.append(event)
            }
        }
        if let tail = parser.finishStream() {
            events.append(tail)
        }

        #expect(events.count == 2)
        #expect(events[0].event == "initial")
        #expect(String(data: events[0].data, encoding: .utf8) == #"{"name":"Kraków"}"#)
        #expect(events[0].retryMs == 5000)

        #expect(events[1].event == "message")
        #expect(String(data: events[1].data, encoding: .utf8) == "line1\nline2")
        #expect(events[1].retryMs == nil)
    }

    @Test("fetchCities hits GET /api6 and decodes cities catalog")
    func testFetchCities() async throws {
        let client = makeClient()
        let capturedURL = LockedValue<URL?>(nil)

        let payload = Data("""
        {
            "hash": "h1",
            "cities": [
                {"id": "krakow", "name": "Kraków", "location": [19.94, 50.06], "timezone": "Europe/Warsaw"},
                {"id": "pkp", "name": "PKP", "location": [21.03, 52.25], "virtual": true}
            ]
        }
        """.utf8)

        let cities = try await MockURLProtocol.withHandler({ request in
            capturedURL.value = request.url
            let response = try StubResponses.http(status: 200, urlString: "https://api.zbiorkom.live/api6")
            return (response, payload)
        }) {
            try await client.fetchCities()
        }

        #expect(capturedURL.value?.absoluteString == "https://api.zbiorkom.live/api6")
        #expect(cities.count == 2)
        #expect(cities[0].id == "krakow")
        #expect(cities[1].isVirtual == true)
    }

    @Test("fetchVehicleMetadata percent-encodes colon in vehicle ID")
    func testFetchVehicleMetadata() async throws {
        let client = makeClient()
        let capturedPath = LockedValue<String?>(nil)
        let payload = Data(#"["3:MM831","MAN Lion's City 18 G",2024,"Mobilis","hash"]"#.utf8)

        let metadata = try await MockURLProtocol.withHandler({ request in
            capturedPath.value = request.url?.absoluteString
            let response = try StubResponses.http(status: 200)
            return (response, payload)
        }) {
            try await client.fetchVehicleMetadata(city: "krakow", vehicleId: "3:MM831")
        }

        #expect(capturedPath.value == "https://api.zbiorkom.live/api6/krakow/vehicles/vehicle/3%3AMM831")
        #expect(metadata.id == "3:MM831")
        #expect(metadata.model == "MAN Lion's City 18 G")
        #expect(metadata.prodYear == 2024)
        #expect(metadata.carrier == "Mobilis")
    }

    @Test("streamMapFeatures builds /{city}/mapFeatures/{zoom}/{bbox}/stream and emits initial + message")
    func testStreamMapFeatures() async throws {
        let client = makeClient()
        let capturedURL = LockedValue<String?>(nil)
        let bbox = BoundingBox(minLon: 21.0, minLat: 52.2, maxLon: 21.1, maxLat: 52.3)

        let ssePayload = """
        retry: 6500

        event: initial
        data: {"stops":[["s1","warsaw","Centrum","01",[21.01,52.23],[3],90]],"suggestedCity":"warsaw"}

        event: message
        data: {"positions":[["v1","warsaw",["520","warsaw","520","Marysin","default",3,"#97160f"],"1",[21.02,52.24],180]],"dots":[],"bbox":[21.0,52.2,21.1,52.3]}

        """

        let events: [MapFeaturesEvent] = try await MockURLProtocol.withHandler({ request in
            capturedURL.value = request.url?.absoluteString
            let response = try StubResponses.sse(urlString: request.url?.absoluteString ?? "https://api.zbiorkom.live/api6")
            return (response, Data(ssePayload.utf8))
        }) {
            var collected: [MapFeaturesEvent] = []
            for try await event in client.streamMapFeatures(city: "warsaw", zoom: 15.0, bbox: bbox) {
                collected.append(event)
            }
            return collected
        }

        #expect(capturedURL.value == "https://api.zbiorkom.live/api6/warsaw/mapFeatures/15/21.000000,52.200000,21.100000,52.300000/stream")
        #expect(events.count == 2)

        guard case .initial(let initial) = events[0],
              case .message(let update) = events[1] else {
            Issue.record("Expected initial followed by message")
            return
        }
        #expect(initial.stops.count == 1)
        #expect(initial.stops[0].hasFullMetadata == false)
        #expect(update.positions.count == 1)
        #expect(update.positions[0].id == "v1")
    }

    @Test("streamStopDepartures hits /{city}/stops/{stopId}/stream?limit=21 and emits 10-tuple initial + departures")
    func testStreamStopDepartures() async throws {
        let client = makeClient()
        let capturedURL = LockedValue<String?>(nil)

        let ssePayload = """
        event: initial
        data: ["s1","krakow","Teatr Słowackiego","01",[19.94,50.06],[0,3],263,"Poczta Główna",[["124","krakow","124","Os. Podwawelskie — Tauron","default",3,"#296d00"]],[]]

        event: message
        data: [[["trip-1","krakow",["124","krakow","124","Os. Podwawelskie — Tauron","default",3,"#296d00"],"Tauron","124-01","",[]],null,[1794433020000,0,0,"B",1]]]

        """

        let events: [StopStreamEvent] = try await MockURLProtocol.withHandler({ request in
            capturedURL.value = request.url?.absoluteString
            let response = try StubResponses.sse(urlString: request.url?.absoluteString ?? "https://api.zbiorkom.live/api6")
            return (response, Data(ssePayload.utf8))
        }) {
            var collected: [StopStreamEvent] = []
            for try await event in client.streamStopDepartures(city: "krakow", stopId: "s1", limit: 21) {
                collected.append(event)
            }
            return collected
        }

        #expect(capturedURL.value == "https://api.zbiorkom.live/api6/krakow/stops/s1/stream?limit=21")
        #expect(events.count == 2)
        guard case .initial(let stop) = events[0],
              case .message(let departures) = events[1] else {
            Issue.record("Expected stop initial and departures")
            return
        }
        #expect(stop.hasFullMetadata == true)
        #expect(stop.direction == "Poczta Główna")
        #expect(departures.count == 1)
        #expect(departures[0].departure.platform == "B")
    }

    @Test("streamVehiclePosition encodes vehicleId with colon and parses TripStreamEvent")
    func testStreamVehiclePosition() async throws {
        let client = makeClient()
        let capturedURL = LockedValue<String?>(nil)

        let ssePayload = """
        event: initial
        data: {"trip":["t1","krakow",["129","krakow","129","Czyżyny — Dworzec","default",3,"#296d00"],"Dworzec Główny Zachód","129-02","",[]],"itinerary":[[[["s1","krakow","Czyżyny","01",[19.98,50.07],[3],90],1,0,""]],"o_pp~Ai}v_e@?g@",[]]}

        event: message
        data: {"position":["3:MM831","krakow",["129","krakow","129","Czyżyny — Dworzec","default",3,"#296d00"],"129-02",[19.95,50.07],108,1794432450000,"t1",55],"stops":[[[1794432400000,60000,1],[1794432400000,60000,1]]],"sequence":0,"alerts":[]}

        """

        let events: [TripStreamEvent] = try await MockURLProtocol.withHandler({ request in
            capturedURL.value = request.url?.absoluteString
            let response = try StubResponses.sse(urlString: request.url?.absoluteString ?? "https://api.zbiorkom.live/api6")
            return (response, Data(ssePayload.utf8))
        }) {
            var collected: [TripStreamEvent] = []
            for try await event in client.streamVehiclePosition(city: "krakow", vehicleId: "3:MM831") {
                collected.append(event)
            }
            return collected
        }

        #expect(capturedURL.value == "https://api.zbiorkom.live/api6/krakow/positions/3%3AMM831/stream")
        #expect(events.count == 2)
    }

    @Test("SSE errorCode event surfaces ZbiorkomAPIError.serverError")
    func testSSEErrorCodeEvent() async throws {
        let client = makeClient()
        let ssePayload = "event: errorCode\ndata: STOP_NOT_FOUND\n\n"

        do {
            try await MockURLProtocol.withHandler({ _ in
                let response = try StubResponses.sse(urlString: "https://api.zbiorkom.live/api6/warsaw/stops/missing/stream")
                return (response, Data(ssePayload.utf8))
            }) {
                for try await _ in client.streamStopDepartures(city: "warsaw", stopId: "missing") {}
            }
            Issue.record("Expected serverError")
        } catch let error as ZbiorkomAPIError {
            #expect(error == .serverError("STOP_NOT_FOUND"))
        }
    }

    @Test("HTTP 404 surfaces httpError without retrying")
    func testHTTP404DoesNotRetry() async throws {
        let client = makeClient()
        let attemptCount = LockedValue(0)

        do {
            _ = try await MockURLProtocol.withHandler({ _ in
                attemptCount.mutate { $0 += 1 }
                return (try StubResponses.http(status: 404), Data())
            }) {
                try await client.fetchVehicleMetadata(city: "warsaw", vehicleId: "missing")
            }
            Issue.record("Expected httpError(404)")
        } catch let error as ZbiorkomAPIError {
            #expect(error == .httpError(statusCode: 404))
            #expect(attemptCount.value == 1)
        }
    }

    @Test("Empty city parameter fails with invalidParameter")
    func testEmptyCityParameterThrows() async throws {
        let client = makeClient()
        do {
            _ = try await client.fetchVehicleMetadata(city: "   ", vehicleId: "v1")
            Issue.record("Expected invalidParameter")
        } catch let error as ZbiorkomAPIError {
            #expect(error == .invalidParameter("city"))
        }
    }
}
