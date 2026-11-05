import Foundation
import SwiftUI

public extension Color {
    /// Parses `RGB` (3 or 6 digit) or `ARGB` (8 digit) hex strings,
    /// with or without a leading `#`. Returns `nil` for anything invalid so
    /// callers must choose an explicit fallback instead of silently getting a
    /// wrong color.
    init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard [3, 6, 8].contains(cleaned.count),
              cleaned.allSatisfy({ $0.isHexDigit })
        else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit shorthand)
            (a, r, g, b) = (255, (value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    /// Convenience for the common "API color with a known-good fallback" case.
    init(hex: String, fallback: Color) {
        self = Color(hex: hex) ?? fallback
    }
}
