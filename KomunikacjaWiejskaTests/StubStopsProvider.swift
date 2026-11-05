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
    private struct State {
        var callCount = 0
        var requestedCities: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let fixtureStops: [Stop]
    private let fixtureError: Error?

    init(stops: [Stop] = [], error: Error? = nil) {
        self.fixtureStops = stops
        self.fixtureError = error
    }

    var callCount: Int {
        state.withLock { $0.callCount }
    }

    var requestedCities: [String] {
        state.withLock { $0.requestedCities }
    }

    func fetchStops(city: String, bbox: BoundingBox?) async throws -> [Stop] {
        state.withLock { testState in
            testState.callCount += 1
            testState.requestedCities.append(city)
        }
        if let fixtureError = fixtureError {
            throw fixtureError
        }
        return fixtureStops
    }
}

@MainActor
enum StopFixtures {
    static func sample(
        id: String = "warsaw-centrum-01",
        city: String = "warsaw",
        name: String = "Testowa",
        code: String = "01",
        bearing: Int? = 90
    ) -> Stop {
        Stop(
            id: id,
            city: city,
            name: name,
            code: code,
            longitude: 21.01,
            latitude: 52.23,
            vehicleTypes: [.bus],
            bearing: bearing,
            direction: "Centrum",
            routes: [],
            entrances: []
        )
    }
}
