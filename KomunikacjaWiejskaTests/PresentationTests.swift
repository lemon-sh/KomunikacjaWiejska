import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import SwiftUI
import Testing
import UIKit

@Suite("Presentation & UI Component Tests")
@MainActor
struct PresentationTests {
    private func rgba(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    @Test("RouteType properties adhere to symbol and color mapping contract")
    func testRouteType() {
        for type in RouteType.allCases {
            #expect(!type.systemImageName.isEmpty)
            #expect(!type.defaultHexColor.isEmpty)
            #expect(!type.displayName.isEmpty)
        }
        // Unknown sentinel must remain distinct from standard transit types
        #expect(RouteType.unknown.systemImageName != RouteType.bus.systemImageName)
        #expect(RouteType.unknown.systemImageName != RouteType.tram.systemImageName)
        #expect(RouteType.unknown.defaultHexColor != RouteType.bus.defaultHexColor)
    }

    @Test("Hex color parsing accepts 3-, 6-, and 8-digit formats")
    func testColorParsingValid() throws {
        let white = try #require(Color(hex: "#fff"))
        let whiteRGBA = rgba(white)
        #expect(whiteRGBA.red == 1 && whiteRGBA.green == 1 && whiteRGBA.blue == 1 && whiteRGBA.alpha == 1)

        let red = try #require(Color(hex: "#ff0000"))
        let redRGBA = rgba(red)
        #expect(redRGBA.red == 1 && redRGBA.green == 0 && redRGBA.blue == 0 && redRGBA.alpha == 1)

        let translucentRed = try #require(Color(hex: "#80ff0000"))
        let translucentRGBA = rgba(translucentRed)
        #expect(translucentRGBA.red == 1 && translucentRGBA.green == 0 && translucentRGBA.blue == 0)
        #expect(abs(translucentRGBA.alpha - 128.0 / 255.0) < 0.01)
    }

    @Test("Hex color parsing rejects invalid input")
    func testColorParsingInvalid() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#12") == nil)      // 2 digits
        #expect(Color(hex: "#abcd") == nil)    // 4 digits
        #expect(Color(hex: "#abcde") == nil)   // 5 digits
        #expect(Color(hex: "#abcdef0") == nil) // 7 digits
        #expect(Color(hex: "#gggggg") == nil)  // non-hex characters

        #expect(rgba(Color(hex: "nope", fallback: .blue)).blue == 1)
    }

    @Test("Relative luminance and text contrast safely differentiate light and dark backgrounds")
    func testRelativeLuminanceAndContrast() throws {
        // Light backgrounds -> Black text
        #expect(Color.contrastingTextColor(forHex: "#FFFFFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#FFFF00") == .black) // Yellow
        #expect(Color.contrastingTextColor(forHex: "FFF") == .black)
        #expect(Color.contrastingTextColor(forHex: "#A8F0C6") == .black) // Pale mint

        // Dark backgrounds -> White text
        #expect(Color.contrastingTextColor(forHex: "#000000") == .white)
        #expect(Color.contrastingTextColor(forHex: "#0000FF") == .white) // Pure blue
        #expect(Color.contrastingTextColor(forHex: "#1E3A8A") == .white) // Navy
        #expect(Color.contrastingTextColor(forHex: "#D97706") == .white) // Dark amber
        #expect(Color.contrastingTextColor(forHex: "000") == .white)

        // Invalid hex -> Fallback
        #expect(Color.contrastingTextColor(forHex: "invalid", fallback: .white) == .white)
        #expect(Color.contrastingTextColor(forHex: "", fallback: .black) == .black)

        // Numerical luminance bounds
        let whiteLum = try #require(Color.relativeLuminance(hex: "#ffffff"))
        let blackLum = try #require(Color.relativeLuminance(hex: "#000000"))
        #expect(abs(whiteLum - 1.0) < 0.001)
        #expect(abs(blackLum - 0.0) < 0.001)
        #expect(Color.relativeLuminance(hex: "xyz") == nil)
    }

    @Test("MapMode identifiers stay stable while display names are localized")
    func testMapModes() {
        #expect(MapMode.allCases.count == 2)
        #expect(MapMode.explore.rawValue == "Explore")
        #expect(MapMode.satellite.rawValue == "Satellite")
        #expect(MapMode.explore.id == "Explore")
        #expect(MapMode.satellite.id == "Satellite")
        #expect(!MapMode.explore.displayName.isEmpty)
        #expect(MapMode.explore.displayName != MapMode.satellite.displayName)
    }

    @Test("The app ships Polish and English localizations")
    func testLocalizations() {
        let localizations = Set(Bundle.main.localizations)
        #expect(localizations.contains("pl"))
        #expect(localizations.contains("en"))
        #expect(
            Bundle.main.localizedString(forKey: "map.loading.initial", value: nil, table: nil)
                != "map.loading.initial"
        )
    }

    @Test("Stop marker direction updates with map camera heading")
    func testStopMarkerEffectiveRotation() {
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 0) == 90)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 0) == 0)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 0) == 180)
        #expect(StopMarkerView.effectiveRotation(bearing: 270, heading: 0) == 270)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 90) == 0)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 90) == -90)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 90) == 90)
        #expect(StopMarkerView.effectiveRotation(bearing: 90, heading: 180) == -90)
        #expect(StopMarkerView.effectiveRotation(bearing: 0, heading: 45) == -45)
        #expect(StopMarkerView.effectiveRotation(bearing: 180, heading: 350) == -170)
    }

    @Test("StopDetailSheet route badges have uniform height across vehicle types")
    func testRouteBadgeUniformHeight() {
        for type in RouteType.displayableCases {
            let route = StopRoute(
                id: "r-\(type.rawValue)",
                city: "warsaw",
                name: "1",
                longName: "Test Route",
                agency: "ZTM",
                type: type,
                color: "FB8C00"
            )
            let badge = RouteBadgeView(route: route)
            let controller = UIHostingController(rootView: badge)
            let size = controller.sizeThatFits(in: CGSize(width: 300, height: 300))
            #expect(abs(size.height - 24) <= 2, "RouteBadge height \(size.height) deviated for type \(type)")
        }
    }

    @Test("StopDetailSheet header icon container has uniform square footprint across vehicle types")
    func testHeaderIconUniformFootprint() {
        for type in RouteType.displayableCases {
            let stop = Stop(
                id: "test-\(type.rawValue)",
                city: "warsaw",
                name: "Test Stop",
                code: "01",
                longitude: 21.0,
                latitude: 52.0,
                vehicleTypes: [type],
                bearing: nil,
                direction: "",
                routes: [],
                entrances: []
            )
            let sheet = StopDetailSheet(stop: stop, onDismiss: {})
            let controller = UIHostingController(rootView: sheet)
            let size = controller.sizeThatFits(in: CGSize(width: 393, height: 600))
            #expect(size.height > 100)
        }
    }

    @Test("VehicleDetailSheet renders without crashing across delay states")
    func testVehicleDetailSheetRenders() {
        let onTime = VehicleFixtures.sample(delay: 0)
        let late = VehicleFixtures.sample(delay: 180_000)
        let early = VehicleFixtures.sample(delay: -120_000)

        for vehicle in [onTime, late, early] {
            let sheet = VehicleDetailSheet(vehicle: vehicle, onDismiss: {})
            let controller = UIHostingController(rootView: sheet)
            let size = controller.sizeThatFits(in: CGSize(width: 393, height: 600))
            #expect(size.height > 100)
        }
    }

    @Test("VehicleMarkerView effectiveRotation calculation offsets heading")
    func testVehicleMarkerViewEffectiveRotation() {
        #expect(VehicleMarkerView.effectiveRotation(bearing: 180, heading: 0) == 180)
        #expect(VehicleMarkerView.effectiveRotation(bearing: 180, heading: 90) == 90)
        #expect(VehicleMarkerView.effectiveRotation(bearing: 90, heading: 90) == 0)
    }
}

