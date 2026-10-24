import XCTest

/// Smoke tests for the app shell. D1 owns this folder from Wave 3.
final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The shell without a backend. B1's live session starts signed out, so these run on the
    /// AppCore preview session, signed in and onboarded (B1, cross-owner, for D1).
    @MainActor
    private func onboardedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-GlowPreviewSession", "ready"]
        return app
    }

    @MainActor
    func testLaunchShowsTheTabs() {
        let app = onboardedApp()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Matches"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testRoomLinkOpensTheJoinScreen() throws {
        let app = onboardedApp()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 10))
        try app.open(XCTUnwrap(URL(string: "glow://r/demo?t=UITEST")))
        XCTAssertTrue(app.staticTexts["Room: demo"].waitForExistence(timeout: 10))
    }
}
