import Foundation

public enum MapConstants {
    /// Approximate metres per degree of latitude (~111 km).
    public static let metresPerDegreeLatitude: Double = 111_000

    /// Debounce applied to viewport stops fetches triggered by camera movements.
    public static let cameraFetchDebounce: Duration = .milliseconds(350)
}

