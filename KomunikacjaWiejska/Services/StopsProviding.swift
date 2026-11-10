import Foundation

/// Abstracts transit data fetching (stops and live vehicle positions) so that `MapViewModel`
/// can be tested hermetically with stubs without hitting the production API.
/// `nonisolated` because the project defaults to MainActor isolation, and network clients
/// are independent actors that must not be constrained to MainActor.
nonisolated protocol TransitDataProviding: Sendable {
    func fetchStops(city: String, bbox: BoundingBox?) async throws -> [Stop]
    func fetchVehicles(city: String, bbox: BoundingBox) async throws -> [VehiclePosition]
}

/// Backwards-compatible alias for existing consumers.
typealias StopsProviding = TransitDataProviding

extension ZbiorkomAPIClient: TransitDataProviding {}
