import Foundation
import SwiftUI

extension Color {
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

    /// Computes the relative luminance of a color from hex string according to WCAG 2.1 definitions (0.0 to 1.0).
    /// Returns nil if the hex string is invalid.
    static func relativeLuminance(hex: String) -> Double? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard [3, 6, 8].contains(cleaned.count),
              cleaned.allSatisfy({ $0.isHexDigit })
        else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let rByte, gByte, bByte: UInt64
        switch cleaned.count {
        case 3:
            (rByte, gByte, bByte) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6:
            (rByte, gByte, bByte) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8:
            (rByte, gByte, bByte) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            return nil
        }

        func channelLuminance(_ byte: UInt64) -> Double {
            let s = Double(byte) / 255.0
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }

        let r = channelLuminance(rByte)
        let g = channelLuminance(gByte)
        let b = channelLuminance(bByte)

        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Selects `.white` or `.black` text color depending on the background color's relative luminance.
    /// Uses the standard WCAG threshold (0.45): light backgrounds receive black text, dark receive white.
    static func contrastingTextColor(forHex hex: String, fallback: Color = .white) -> Color {
        guard let luminance = relativeLuminance(hex: hex) else {
            return fallback
        }
        return luminance > 0.45 ? .black : .white
    }
}
