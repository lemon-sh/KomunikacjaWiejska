import SwiftUI

@main
struct KomunikacjaWiejskaApp: App {
    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        WindowGroup {
            if isTesting {
                Color.clear
            } else {
                TransitMapView()
            }
        }
    }
}

