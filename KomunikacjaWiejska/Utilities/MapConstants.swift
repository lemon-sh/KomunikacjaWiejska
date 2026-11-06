import Foundation

enum MapConstants {
    /// Approximate metres per degree of latitude (~111 km).
    static let metresPerDegreeLatitude: Double = 111_000

    /// Debounce applied to viewport stops fetches triggered by camera movements.
    static let cameraFetchDebounce: Duration = .milliseconds(350)
}

