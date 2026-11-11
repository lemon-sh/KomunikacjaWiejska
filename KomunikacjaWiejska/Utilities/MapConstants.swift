import CoreFoundation
import Foundation

/// Constants governing SSE streaming, viewport zoom derivation, and map markers.
nonisolated enum MapConstants {
    /// Default city identifier selected on first launch before `/api6` resolves if none is persisted.
    static let defaultCityID: String = "warsaw"

    /// Initial camera center coordinates used while `GET /api6` loads on first launch.
    static let defaultCenterLatitude: Double = 52.2297
    static let defaultCenterLongitude: Double = 21.0122

    /// Default coordinate span delta for initial city framing.
    static let defaultCoordinateSpanDelta: Double = 0.08

    /// Camera altitude (meters) when focusing on the user's current location.
    static let userFocusDistance: Double = 1_500

    /// Default camera altitude (meters) when jumping to a city center.
    static let defaultCityDistance: Double = 3_000

    /// Distance beyond which the city suggestion alert becomes eligible to reappear.
    static let dismissalResetDistanceMeters: Double = 5_000

    /// Minimum time the camera must stay settled before reopening `mapFeatures` SSE.
    static let cameraDebounce: Duration = .milliseconds(350)

    /// Fallback animation/render wait duration cleanly handled by SwiftUI MapKit.
    static let defaultViewportWidthPoints: Double = 393.0

    /// Background grace period before pausing active SSE streams (matches webapp `45_000` ms).
    static let sseBackgroundDisconnectDelay: Duration = .seconds(45)

    /// Elapsed background/idle threshold triggering SSE refresh on foreground return (matches webapp `10_000` ms).
    static let sseForegroundStaleInterval: TimeInterval = 10.0

    /// Maximum automatic SSE reconnect attempts on transient stream drops (matches webapp 5 retries).
    static let sseMaxReconnectAttempts: Int = 5

    /// Delay before attempting automatic SSE reconnection (matches webapp `2_000` ms).
    static let sseReconnectDelay: Duration = .seconds(2)

    /// Default stop departure count requested from `stops/{id}/stream`.
    static let defaultStopDeparturesLimit: Int = 21

    /// Diameter in points for zoomed-out server `dots` vehicle markers.
    static let dotMarkerSize: CGFloat = 8

    /// Diameter in points for stop nodes drawn along a selected trip itinerary.
    static let itineraryStopMarkerSize: CGFloat = 10
}
