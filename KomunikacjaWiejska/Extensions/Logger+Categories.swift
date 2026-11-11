import Foundation
import os

extension Logger {
    private nonisolated static let subsystem = "KomunikacjaWiejska"

    /// Logger dedicated to map viewport streaming and camera state.
    nonisolated static let mapViewport = Logger(subsystem: subsystem, category: "MapViewport")

    /// Logger dedicated to API requests, HTTP transport, and response decoding.
    nonisolated static let api = Logger(subsystem: subsystem, category: "API")

    /// Logger dedicated to city catalog loading and city resolution.
    nonisolated static let catalog = Logger(subsystem: subsystem, category: "Catalog")
}
