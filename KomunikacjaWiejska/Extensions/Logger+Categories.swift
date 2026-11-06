import Foundation
import os

extension Logger {
    private nonisolated static let subsystem = "KomunikacjaWiejska"

    /// Logger dedicated to map viewport caching and tile coverage.
    nonisolated static let mapCache = Logger(subsystem: subsystem, category: "MapCache")

    /// Logger dedicated to API requests, HTTP transport, and response decoding.
    nonisolated static let api = Logger(subsystem: subsystem, category: "API")

    /// Logger dedicated to city catalog loading and city resolution.
    nonisolated static let catalog = Logger(subsystem: subsystem, category: "Catalog")
}
