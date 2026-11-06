import Foundation
import CoreLocation
import MapKit
@testable import KomunikacjaWiejska
import Testing

/// Bounded polling helper replacing unconstrained spin-wait loops (2P6-1).
func waitUntil(
    timeout: Duration = .seconds(3),
    pollInterval: Duration = .milliseconds(10),
    _ condition: () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
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

/// Test-only convenience conversion from MKCoordinateRegion to BoundingBox.
extension BoundingBox {
    init?(region: MKCoordinateRegion) {
        let latitudeDelta = region.span.latitudeDelta
        let longitudeDelta = region.span.longitudeDelta
        guard latitudeDelta.isFinite, longitudeDelta.isFinite,
              latitudeDelta > 0, longitudeDelta > 0
        else { return nil }

        let minLon = region.center.longitude - longitudeDelta / 2
        let maxLon = region.center.longitude + longitudeDelta / 2
        let minLat = region.center.latitude - latitudeDelta / 2
        let maxLat = region.center.latitude + latitudeDelta / 2

        self.init(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }
}

