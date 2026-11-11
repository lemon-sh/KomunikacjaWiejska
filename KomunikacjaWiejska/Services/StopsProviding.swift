import Foundation

/// Service abstraction for city catalog loading, vehicle metadata, and live transit SSE streams.
nonisolated protocol TransitDataProviding: Sendable {
    func fetchCities() async throws -> [City]
    func streamMapFeatures(city: String, zoom: Double, bbox: BoundingBox) -> AsyncThrowingStream<MapFeaturesEvent, Error>
    func streamStopDepartures(city: String, stopId: String, limit: Int) -> AsyncThrowingStream<StopStreamEvent, Error>
    func streamVehiclePosition(city: String, vehicleId: String) -> AsyncThrowingStream<TripStreamEvent, Error>
    func streamTrip(city: String, tripId: String) -> AsyncThrowingStream<TripStreamEvent, Error>
    func fetchVehicleMetadata(city: String, vehicleId: String) async throws -> VehicleMetadata
}
