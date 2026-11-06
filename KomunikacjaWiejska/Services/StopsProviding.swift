import Foundation

/// Abstracts the stops data source so that `MapViewModel` can be constructed
/// with a stub in tests instead of touching the production API.
/// `nonisolated` because the project defaults to MainActor isolation, and the
/// client is an independent `actor` that must not be constrained to MainActor.
nonisolated protocol StopsProviding: Sendable {
    func fetchStops(city: String, bbox: BoundingBox?) async throws -> [Stop]
}

extension ZbiorkomAPIClient: StopsProviding {}
