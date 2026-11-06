import CoreLocation
import Foundation
@testable import KomunikacjaWiejska
import Testing

@Suite("Location State & Manager Tests")
@MainActor
struct LocationStateTests {
    @Test("Location authorization state maps prompts, denial, and authorization")
    func testLocationAuthorizationState() {
        #expect(LocationAuthorizationState.resolve(status: .notDetermined) == .notDetermined)
        #expect(LocationAuthorizationState.resolve(status: .authorizedWhenInUse) == .authorized)
        #expect(LocationAuthorizationState.resolve(status: .authorizedAlways) == .authorized)
        #expect(LocationAuthorizationState.resolve(status: .denied) == .denied)
        #expect(LocationAuthorizationState.resolve(status: .restricted) == .denied)
    }

    @Test("The location permission prompt is localized in both languages")
    func testLocationUsageDescriptionLocalization() throws {
        let enPath = try #require(
            Bundle.main.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "en"
            )
        )
        let plPath = try #require(
            Bundle.main.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: "pl"
            )
        )
        let enStrings = try #require(NSDictionary(contentsOfFile: enPath) as? [String: String])
        let plStrings = try #require(NSDictionary(contentsOfFile: plPath) as? [String: String])

        let key = "NSLocationWhenInUseUsageDescription"
        #expect(enStrings[key]?.isEmpty == false)
        #expect(plStrings[key]?.isEmpty == false)
        #expect(enStrings[key] != plStrings[key])
    }

    @Test("Location timeout is bounded to 15 seconds")
    func testLocationTimeoutBound() {
        #expect(LocationManager.requestTimeout == .seconds(15))
    }
}

