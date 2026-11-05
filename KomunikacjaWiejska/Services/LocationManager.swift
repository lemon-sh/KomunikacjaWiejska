import CoreLocation
import Foundation
import os

/// How the app may currently access (or not access) the user's position.
public enum LocationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case servicesDisabled
}

@Observable
@MainActor
public final class LocationManager: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()

    private static let logger = Logger(subsystem: "KomunikacjaWiejska", category: "Location")

    private let manager = CLLocationManager()
    public var authorizationStatus: CLAuthorizationStatus
    public var userLocation: CLLocation?
    /// Set when the last one-shot fix failed with a user-recoverable reason.
    public var locationAccessDenied: Bool

    override private init() {
        self.authorizationStatus = manager.authorizationStatus
        self.locationAccessDenied = false
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Derived, UI-friendly view of what the location button should do.
    public var authorizationState: LocationAuthorizationState {
        guard CLLocationManager.locationServicesEnabled() else {
            return .servicesDisabled
        }
        switch authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public func requestWhenInUseAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot fix for centering the camera. Does not keep GPS running while
    /// the user is not actively tracking; battery-friendly.
    public func requestLocationUpdate() {
        guard authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways else {
            Self.logger.info("Location fix requested while not authorized")
            return
        }
        manager.requestLocation()
    }

    public func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationState == .authorized {
            locationAccessDenied = false
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.logger.error("Location update failed: \(String(describing: error), privacy: .public)")
        if let cleError = error as? CLError, cleError.code == .denied {
            locationAccessDenied = true
        }
    }
}
