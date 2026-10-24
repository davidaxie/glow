import XCTest

/// Smoke tests for the app shell. D1 owns this folder from Wave 3.
final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabs() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Matches"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    @MainActor
    func testRoomLinkOpensTheJoinScreen() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 10))
        try app.open(XCTUnwrap(URL(string: "glow://r/demo?t=UITEST")))
        XCTAssertTrue(app.staticTexts["Room: demo"].waitForExistence(timeout: 10))
    }
}
