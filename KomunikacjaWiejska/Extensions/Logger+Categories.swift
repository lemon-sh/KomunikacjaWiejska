import Foundation
import os

extension Logger {
    private nonisolated static let subsystem = "KomunikacjaWiejska"

    /// Logger dedicated to map viewport caching, tile coverage, thinning, and cache invalidation.
    nonisolated public static let mapCache = Logger(subsystem: subsystem, category: "MapCache")

    /// Logger dedicated to API requests, HTTP transport, and response decoding.
    nonisolated public static let api = Logger(subsystem: subsystem, category: "API")
}

