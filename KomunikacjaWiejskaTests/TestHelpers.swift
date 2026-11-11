import Foundation
import CoreLocation
import MapKit
@testable import KomunikacjaWiejska
import Testing

/// Bounded polling helper replacing unconstrained spin-wait loops (2P6-1).
func waitUntil(
    timeout: Duration = .seconds(3),
    pollInterval: Duration = .milliseconds(5),
    _ condition: () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if try await condition() {
            return
        }
        await Task.yield()
        if try await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    #expect(Bool(false), "Condition not met within \(timeout)")
}

/// Convenience polling helper that waits for MapViewModel to exit its loading state.
@MainActor
func waitUntilLoaded(
    _ viewModel: MapViewModel,
    timeout: Duration = .seconds(3)
) async throws {
    try await waitUntil(timeout: timeout) {
        !viewModel.isLoading
    }
}


