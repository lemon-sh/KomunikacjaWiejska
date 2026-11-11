import Foundation
import SwiftUI

/// Shared time, countdown, delay, and ping-age formatting for `StopDetailSheet` and `VehicleDetailSheet`.

nonisolated enum TransitDelayPresentation: Equatable, Sendable {
    case onTime
    case delayed(minutes: Int)
    case early(minutes: Int)
    case scheduled
    case cancelled

    var color: Color {
        switch self {
        case .onTime: .green
        case .delayed: .red
        case .early: .orange
        case .scheduled: .secondary
        case .cancelled: .red
        }
    }

    var shouldHighlightText: Bool {
        switch self {
        case .delayed, .early, .cancelled: true
        case .onTime, .scheduled: false
        }
    }

    var shouldStrikeScheduledTime: Bool {
        switch self {
        case .delayed, .early, .cancelled: true
        case .onTime, .scheduled: false
        }
    }

    var localizedText: String {
        switch self {
        case .onTime:
            return String(localized: "vehicle.delay.onTime")
        case .delayed(let minutes):
            return String(format: String(localized: "vehicle.delay.minutesLate"), minutes)
        case .early(let minutes):
            return String(format: String(localized: "vehicle.delay.minutesEarly"), minutes)
        case .scheduled:
            return String(localized: "vehicle.status.scheduled")
        case .cancelled:
            return String(localized: "vehicle.status.cancelled")
        }
    }
}

nonisolated enum TransitTimeFormatting {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var clockFormatters: [String: DateFormatter] = [:]

    /// Formats epoch milliseconds as 24-hour `HH:mm` in the specified `TimeZone`.
    static func formattedClockTime(epochMs: Int64, timeZone: TimeZone = .current) -> String {
        let formatter: DateFormatter = lock.withLock {
            if let existing = clockFormatters[timeZone.identifier] {
                return existing
            }
            let newFormatter = DateFormatter()
            newFormatter.locale = Locale(identifier: "en_GB")
            newFormatter.timeZone = timeZone
            newFormatter.dateFormat = "HH:mm"
            clockFormatters[timeZone.identifier] = newFormatter
            return newFormatter
        }
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1_000.0)
        return lock.withLock { formatter.string(from: date) }
    }

    /// Computes whole minutes remaining rounded to nearest minute (`<1` when <= 0).
    static func countdownText(estimatedMs: Int64, now: Date = Date()) -> String {
        let nowMs = Int64(now.timeIntervalSince1970 * 1_000.0)
        let diffMs = estimatedMs - nowMs
        let minutes = Int((Double(diffMs) / 60_000.0).rounded())
        if minutes <= 0 {
            return String(localized: "vehicle.countdown.lessThanOne")
        }
        return "\(minutes)"
    }

    static func minutesRemaining(estimatedMs: Int64, now: Date = Date()) -> Int {
        let nowMs = Int64(now.timeIntervalSince1970 * 1_000.0)
        return Int((Double(estimatedMs - nowMs) / 60_000.0).rounded())
    }

    static func presentation(for time: StopTimeUpdate) -> TransitDelayPresentation {
        if time.status == .cancelled {
            return .cancelled
        }
        if time.status == .scheduled {
            return .scheduled
        }
        let delayMs = time.delayMs ?? 0
        let minutes = Int(delayMs / 60_000)
        if minutes > 0 {
            return .delayed(minutes: minutes)
        } else if minutes < 0 {
            return .early(minutes: abs(minutes))
        }
        return .onTime
    }

    static func relativePingDescription(lastPingMs: Int64, now: Date = Date()) -> String {
        let ageSeconds = max(0, Int(now.timeIntervalSince1970 - Double(lastPingMs) / 1_000.0))
        if ageSeconds < 5 {
            return String(format: String(localized: "vehicle.lastPing"), String(localized: "vehicle.lastPing.justNow"))
        } else if ageSeconds < 60 {
            let relative = String(format: String(localized: "vehicle.lastPing.seconds"), Int64(ageSeconds))
            return String(format: String(localized: "vehicle.lastPing"), relative)
        } else {
            let mins = Int64(ageSeconds / 60)
            let relative = String(format: String(localized: "vehicle.lastPing.minutes"), mins)
            return String(format: String(localized: "vehicle.lastPing"), relative)
        }
    }
}
