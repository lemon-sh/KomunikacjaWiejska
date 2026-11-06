import Foundation
import os
@testable import KomunikacjaWiejska

/// Thread-safe mutable value for capturing URL-protocol handler state.
/// All access goes through `OSAllocatedUnfairLock`, so the unchecked
/// `Sendable` conformance is safe.
final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        self.lock = OSAllocatedUnfairLock(initialState: value)
    }

    var value: Value {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    func mutate(_ body: @Sendable (inout Value) -> Void) {
        lock.withLock { body(&$0) }
    }
}

/// `URLProtocol` stub so API-client tests exercise the real `URLSession` code
/// paths without opening a socket. The suite using it is serialized because
/// `handler` is process-wide state.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func withHandler<T>(
        _ handler: @escaping (URLRequest) throws -> (URLResponse, Data),
        operation: () async throws -> T
    ) async rethrows -> T {
        self.handler = handler
        defer { self.handler = nil }
        return try await operation()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

enum StubResponses {
    struct FixtureError: Error {}

    static func http(status: Int = 200) throws -> HTTPURLResponse {
        guard let url = URL(string: "https://api.zbiorkom.live/api6-open/warsaw/stops"),
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
              )
        else {
            throw FixtureError()
        }
        return response
    }

    static func nonHTTP() throws -> URLResponse {
        guard let url = URL(string: "https://api.zbiorkom.live/api6-open/warsaw/stops") else {
            throw FixtureError()
        }
        return URLResponse(
            url: url,
            mimeType: "application/json",
            expectedContentLength: 0,
            textEncodingName: nil
        )
    }

    static let validStopsJSON = Data("""
    {
        "stops": [
            [
                "rybnik-srodmiescie-dworek261-0-j58h8",
                "rybnik",
                "Rybnik Śródmieście Dworek",
                "261/0",
                [18.542289, 50.096472],
                [3],
                145,
                "Chwałowice / Boguszowice",
                [],
                []
            ]
        ]
    }
    """.utf8)
}
