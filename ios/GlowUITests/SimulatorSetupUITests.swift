import XCTest

/// Not a product test: `scripts/sim.sh allow-push` runs this to grant notification permission on a
/// Simulator, because `simctl privacy` can't. Passes whether or not the prompt appears.
final class SimulatorSetupUITests: XCTestCase {
    @MainActor
    func testAllowNotifications() {
        let app = XCUIApplication()
        app.launchArguments += ["-GlowDebugAskForNotifications", "YES"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
