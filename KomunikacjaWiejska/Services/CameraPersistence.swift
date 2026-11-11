import CoreLocation
import Foundation

/// Injected abstraction for persisting camera coordinates and user preferences.
protocol CameraPersistenceStore: Sendable {
    func loadLastSelectedCityID() -> String?
    func saveLastSelectedCityID(_ id: String)
    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)?
    func saveCamera(latitude: Double, longitude: Double, distance: Double)
}

/// Production implementation backed by UserDefaults.
final class UserDefaultsCameraPersistenceStore: CameraPersistenceStore, @unchecked Sendable {
    private enum Key {
        static let lastSelectedCityID = "lastSelectedCityId"
        static let savedCameraLatitude = "savedCameraLatitude"
        static let savedCameraLongitude = "savedCameraLongitude"
        static let savedCameraDistance = "savedCameraDistance"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLastSelectedCityID() -> String? {
        defaults.string(forKey: Key.lastSelectedCityID)
    }

    func saveLastSelectedCityID(_ id: String) {
        defaults.set(id, forKey: Key.lastSelectedCityID)
    }

    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)? {
        let lat = defaults.double(forKey: Key.savedCameraLatitude)
        let lon = defaults.double(forKey: Key.savedCameraLongitude)
        let dist = defaults.double(forKey: Key.savedCameraDistance)
        guard lat != 0, lon != 0, dist > 0 else { return nil }
        return (lat, lon, dist)
    }

    func saveCamera(latitude: Double, longitude: Double, distance: Double) {
        defaults.set(latitude, forKey: Key.savedCameraLatitude)
        defaults.set(longitude, forKey: Key.savedCameraLongitude)
        defaults.set(distance, forKey: Key.savedCameraDistance)
    }
}

/// Ephemeral in-memory store for hermetic unit testing without touching UserDefaults.
final class InMemoryCameraPersistenceStore: CameraPersistenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var lastCityID: String?
    private var savedCamera: (latitude: Double, longitude: Double, distance: Double)?

    init(
        initialCityID: String? = nil,
        savedCamera: (latitude: Double, longitude: Double, distance: Double)? = nil
    ) {
        self.lastCityID = initialCityID
        self.savedCamera = savedCamera
    }

    func loadLastSelectedCityID() -> String? {
        lock.withLock { lastCityID }
    }

    func saveLastSelectedCityID(_ id: String) {
        lock.withLock { lastCityID = id }
    }

    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)? {
        lock.withLock { savedCamera }
    }

    func saveCamera(latitude: Double, longitude: Double, distance: Double) {
        lock.withLock { savedCamera = (latitude, longitude, distance) }
    }
}
