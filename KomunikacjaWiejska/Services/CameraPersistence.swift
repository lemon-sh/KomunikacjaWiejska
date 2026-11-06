import Foundation
import CoreLocation

/// Centralised keys for persistent defaults storage.
enum DefaultsKey {
    static let lastSelectedCityID = "lastSelectedCityId"
    static let savedCameraLatitude = "savedCameraLatitude"
    static let savedCameraLongitude = "savedCameraLongitude"
    static let savedCameraDistance = "savedCameraDistance"
}

/// Injected abstraction for persisting camera coordinates and user preferences.
protocol CameraPersistenceStore: Sendable {
    func loadLastSelectedCityID() -> String?
    func saveLastSelectedCityID(_ id: String)
    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)?
    func saveCamera(latitude: Double, longitude: Double, distance: Double)
    func clearCamera()
}

/// Production implementation backed by UserDefaults.
final class UserDefaultsCameraPersistenceStore: CameraPersistenceStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadLastSelectedCityID() -> String? {
        defaults.string(forKey: DefaultsKey.lastSelectedCityID)
    }

    func saveLastSelectedCityID(_ id: String) {
        defaults.set(id, forKey: DefaultsKey.lastSelectedCityID)
    }

    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)? {
        let lat = defaults.double(forKey: DefaultsKey.savedCameraLatitude)
        let lon = defaults.double(forKey: DefaultsKey.savedCameraLongitude)
        let dist = defaults.double(forKey: DefaultsKey.savedCameraDistance)
        guard lat != 0, lon != 0, dist > 0 else { return nil }
        return (lat, lon, dist)
    }

    func saveCamera(latitude: Double, longitude: Double, distance: Double) {
        defaults.set(latitude, forKey: DefaultsKey.savedCameraLatitude)
        defaults.set(longitude, forKey: DefaultsKey.savedCameraLongitude)
        defaults.set(distance, forKey: DefaultsKey.savedCameraDistance)
    }

    func clearCamera() {
        defaults.removeObject(forKey: DefaultsKey.savedCameraLatitude)
        defaults.removeObject(forKey: DefaultsKey.savedCameraLongitude)
        defaults.removeObject(forKey: DefaultsKey.savedCameraDistance)
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
        lock.lock()
        defer { lock.unlock() }
        return lastCityID
    }

    func saveLastSelectedCityID(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        lastCityID = id
    }

    func loadSavedCamera() -> (latitude: Double, longitude: Double, distance: Double)? {
        lock.lock()
        defer { lock.unlock() }
        return savedCamera
    }

    func saveCamera(latitude: Double, longitude: Double, distance: Double) {
        lock.lock()
        defer { lock.unlock() }
        savedCamera = (latitude, longitude, distance)
    }

    func clearCamera() {
        lock.lock()
        defer { lock.unlock() }
        savedCamera = nil
    }
}
