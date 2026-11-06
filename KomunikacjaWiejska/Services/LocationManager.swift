import CoreLocation
import Foundation
import os

/// How the app may currently access (or not access) the user's position.
public enum LocationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized

    /// Pure mapping so the policy can be unit-tested without instantiating
    /// `CLLocationManager`.
    ///
    /// Disabling Location Services system-wide makes Core Location report
    /// `.denied` to the delegate, so a separate `locationServicesEnabled()`
    /// check is redundant — and that call must not run on the main thread.
    public static func resolve(status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
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
}

/// Failures the location button can surface to the user.
public enum LocationError: LocalizedError, Equatable, Sendable {
    case denied
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .denied:
            return String(localized: "location.alert.message")
        case .unavailable:
            return String(localized: "location.error.message")
        }
    }
}

@Observable
@MainActor
public final class LocationManager: NSObject, CLLocationManagerDelegate, LocationProviding {
    public static let shared = LocationManager()

    private static let logger = Logger(subsystem: "KomunikacjaWiejska", category: "Location")
    /// A cached fix younger than this is reused instead of starting GPS again.
    private static let freshFixMaxAge: TimeInterval = 30

    private let manager = CLLocationManager()
    public var authorizationStatus: CLAuthorizationStatus
    public var userLocation: CLLocation?
    public private(set) var isRequestingLocation: Bool = false

    /// Maximum duration to wait for an authorization decision or a one-shot fix before failing with `.unavailable`.
    public static let requestTimeout: Duration = .seconds(15)

    /// Single pending prompt/fix continuation. A button tap can never leave a
    /// continuation stranded: a newer request resumes the previous one first.
    @ObservationIgnored private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    @ObservationIgnored private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Derived, UI-friendly view of what the location button should do.
    public var authorizationState: LocationAuthorizationState {
        LocationAuthorizationState.resolve(status: authorizationStatus)
    }

    public func requestWhenInUseAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Resolves the current position for a one-shot camera centering.
    ///
    /// Requests authorization when necessary and waits for the user's answer,
    /// so a tap that starts from `.notDetermined` still centers the map once
    /// permission is granted. Returns a recent fix when one is already
    /// available; otherwise a single `requestLocation()` is issued.
    ///
    /// Guarded against concurrent taps: if a request is already active,
    /// duplicate concurrent calls throw `.unavailable`. Times out after 15 s.
    public func requestCurrentLocation() async throws -> CLLocation {
        guard !isRequestingLocation else {
            throw LocationError.unavailable
        }
        isRequestingLocation = true
        defer { isRequestingLocation = false }

        return try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask {
                try await self.performLocationRequest()
            }
            group.addTask {
                try await Task.sleep(for: Self.requestTimeout)
                throw LocationError.unavailable
            }
            guard let result = try await group.next() else {
                throw LocationError.unavailable
            }
            group.cancelAll()
            return result
        }
    }

    private func performLocationRequest() async throws -> CLLocation {
        switch authorizationState {
        case .denied:
            throw LocationError.denied
        case .notDetermined:
            let status = await awaitAuthorizationDecision()
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                break
            case .denied, .restricted:
                throw LocationError.denied
            case .notDetermined:
                throw LocationError.unavailable
            @unknown default:
                throw LocationError.denied
            }
        case .authorized:
            break
        }

        if let userLocation,
           abs(Date.now.timeIntervalSince(userLocation.timestamp)) < Self.freshFixMaxAge {
            return userLocation
        }
        return try await requestOneShotFix()
    }

    /// Kept for scene-phase handling; the app requests one-shot fixes rather
    /// than continuous updates, so this is normally a no-op.
    public func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Continuation plumbing

    private func awaitAuthorizationDecision() async -> CLAuthorizationStatus {
        if authorizationStatus != .notDetermined {
            return authorizationStatus
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Replace a stale waiter rather than leaking it.
                authorizationContinuation?.resume(returning: authorizationStatus)
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        } onCancel: {
            Task { @MainActor in
                if let continuation = self.authorizationContinuation {
                    self.authorizationContinuation = nil
                    continuation.resume(returning: self.authorizationStatus)
                }
            }
        }
    }

    private func requestOneShotFix() async throws -> CLLocation {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationContinuation?.resume(throwing: LocationError.unavailable)
                locationContinuation = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in
                if let continuation = self.locationContinuation {
                    self.locationContinuation = nil
                    continuation.resume(throwing: LocationError.unavailable)
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard manager.authorizationStatus != .notDetermined,
              let continuation = authorizationContinuation
        else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: location)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Self.logger.error("Location update failed: \(String(describing: error), privacy: .public)")
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        if let cleError = error as? CLError, cleError.code == .denied {
            continuation.resume(throwing: LocationError.denied)
        } else {
            continuation.resume(throwing: LocationError.unavailable)
        }
    }
}
