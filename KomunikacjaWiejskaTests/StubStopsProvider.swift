import Foundation
import os
@testable import KomunikacjaWiejska

/// In-memory stand-in for `ZbiorkomAPIClient`. Records every request so tests
/// can assert call counts, and either returns a fixture set or throws a
/// configured error. Never touches the network.
///
/// Lock-guarded (rather than an actor) because the project compiles with
/// MainActor default isolation, under which actor conformances to the
/// `nonisolated` `StopsProviding` protocol trip unhelpful isolation errors.
/// `@unchecked Sendable` is justified by the `OSAllocatedUnfairLock`.
final class StubStopsProvider: StopsProviding, @unchecked Sendable {
    /// Gate for simulating in-flight requests. When `holdsRequests` is true,
    /// every `fetchStops` call parks on a continuation until `openGate()`.
    /// Mutable state is only touched while holding `gate`, so unchecked
    /// Sendable is safe and required by `OSAllocatedUnfairLock` in Swift 6.
    private final class Gate: @unchecked Sendable {
        var holdsRequests: Bool
        var parked: [CheckedContinuation<Void, Never>] = []

        init(holdsRequests: Bool) {
            self.holdsRequests = holdsRequests
        }
    }

    private struct State {
        var callCount = 0
        var requestedCities: [String] = []
        var requestedBBoxes: [BoundingBox?] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let gate: OSAllocatedUnfairLock<Gate>
    private let fixtureStops: [Stop]
    private let fixtureError: Error?
    private let fixturesByCity: [String: Result<[Stop], Error>]
    /// Replaces every fixture after construction, so tests can simulate a
    /// refresh returning updated details for the same stop IDs.
    private let overrideStops = OSAllocatedUnfairLock<[Stop]?>(initialState: nil)

    init(
        stops: [Stop] = [],
        error: Error? = nil,
        resultsByCity: [String: Result<[Stop], Error>] = [:],
        holdsRequests: Bool = false
    ) {
        self.fixtureStops = stops
        self.fixtureError = error
        self.fixturesByCity = resultsByCity
        self.gate = OSAllocatedUnfairLock(initialState: Gate(holdsRequests: holdsRequests))
    }

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    var requestedCities: [String] {
        state.withLock { $0.requestedCities }
    }

    var requestedBBoxes: [BoundingBox?] {
        state.withLock { $0.requestedBBoxes }
    }

    func fetchStops(city: String, bbox: BoundingBox?) async throws -> [Stop] {
        let result: Result<[Stop], Error> = state.withLock { testState in
            testState.callCount += 1
            testState.requestedCities.append(city)
            testState.requestedBBoxes.append(bbox)
            return fixtureResult(for: city)
        }
        if gate.withLock({ $0.holdsRequests }) {
            await waitForGate()
        }
        return try result.get()
    }

    private func fixtureResult(for city: String) -> Result<[Stop], Error> {
        if let override = overrideStops.withLock({ $0 }) {
            return .success(override)
        }
        if let result = fixturesByCity[city] {
            return result
        }
        if let fixtureError = fixtureError {
            return .failure(fixtureError)
        }
        return .success(fixtureStops)
    }

    /// Changes what every subsequent request returns.
    func setStops(_ stops: [Stop]) {
        overrideStops.withLock { $0 = stops }
    }

    /// Parks the calling task while the gate holds requests.
    private func waitForGate() async {
        await withCheckedContinuation { continuation in
            let parked: Bool = gate.withLock { gateState in
                if gateState.holdsRequests {
                    gateState.parked.append(continuation)
                    return true
                }
                return false
            }
            if !parked {
                // The gate opened in the meantime; resume immediately.
                continuation.resume()
            }
        }
    }

    /// Makes subsequent requests park again (used for multi-phase tests).
    func holdRequests() {
        gate.withLock { $0.holdsRequests = true }
    }

    /// Releases every parked request and stops holding future ones.
    func openGate() {
        let toResume: [CheckedContinuation<Void, Never>] = gate.withLock { gateState in
            gateState.holdsRequests = false
            let parked = gateState.parked
            gateState.parked = []
            return parked
        }
        toResume.forEach { $0.resume() }
    }
}

@MainActor
enum StopFixtures {
    static func sample(
        id: String = "warsaw-centrum-01",
        city: String = "warsaw",
        name: String = "Testowa",
        code: String = "01",
        bearing: Int? = 90,
        longitude: Double = 21.01,
        latitude: Double = 52.23
    ) -> Stop {
        Stop(
            id: id,
            city: city,
            name: name,
            code: code,
            longitude: longitude,
            latitude: latitude,
            vehicleTypes: [.bus],
            bearing: bearing,
            direction: "Centrum",
            routes: [],
            entrances: []
        )
    }
}
