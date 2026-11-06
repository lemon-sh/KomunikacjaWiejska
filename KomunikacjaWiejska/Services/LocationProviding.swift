import CoreLocation
import Foundation

/// Protocol abstracting device location services for views and view models,
/// enabling fully hermetic testing without initializing CLLocationManager.
@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var authorizationState: LocationAuthorizationState { get }
    var isRequestingLocation: Bool { get }
    var userLocation: CLLocation? { get }

    func requestCurrentLocation() async throws -> CLLocation
    func requestWhenInUseAuthorization()
    func stopUpdatingLocation()
}

