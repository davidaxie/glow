import XCTest

/// Plays Blind mode's moments at a human pace so `scripts/video/ui-capture.py` can record them for
/// the demo video (V1). Every launch runs on the Debug-only Blind mock (`-GlowDebugBlind`, generated
/// portraits, no real people, no network). These are recordings, not checks: run them on their own,
/// `scripts/sim.sh test GlowUITests/DemoVideoUITests`, never as part of the regular suite's gate.
final class DemoVideoUITests: XCTestCase {
    private let fox = "b1c40000-0000-4000-8000-000000000001"
    private let comet = "b1c40000-0000-4000-8000-000000000002"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Recordings only: skipped in the regular suite. ui-capture.py sets TEST_RUNNER_GLOW_DEMO_VIDEO=1,
        // which xcodebuild hands to the test runner as GLOW_DEMO_VIDEO.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GLOW_DEMO_VIDEO"] == "1", "Demo video recordings only")
    }

    @MainActor
    private func launch(_ scenario: String, route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GlowPreviewSession", "ready", "-GlowDebugBlind", scenario, "-GlowDebugRoute", route]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// A slow, human drag across the top card.
    @MainActor
    private func drag(_ card: XCUIElement, toRight: Bool) {
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = card.coordinate(withNormalizedOffset: CGVector(dx: toRight ? 1.6 : -0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
    }

    /// Photo-only cards: like, love, pass, like.
    @MainActor
    func testDemo1BlindDeckSwipes() {
        let app = launch("swiping", route: "blind")
        let top = element(app, "blind.deck.topCard")
        XCTAssertTrue(top.waitForExistence(timeout: 20))
        pause(2.5)
        XCTContext.runActivity(named: "DEMO swipe right") { _ in drag(top, toRight: true) }
        pause(1.6)
        XCTContext.runActivity(named: "DEMO love") { _ in element(app, "blind.deck.love").tap() }
        pause(1.6)
        XCTContext.runActivity(named: "DEMO swipe left") { _ in drag(element(app, "blind.deck.topCard"), toRight: false) }
        pause(1.6)
        XCTContext.runActivity(named: "DEMO swipe right") { _ in drag(element(app, "blind.deck.topCard"), toRight: true) }
        pause(3)
    }

    /// A blind chat: typing your handle brings up the give-away warning; then a one-sided Reveal waits.
    @MainActor
    func testDemo2BlindGiveAwayAndWaiting() {
        let app = launch("chatting", route: "blindChat/\(comet)")
        let input = element(app, "blind.chat.input")
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        pause(2.5)
        input.tap()
        pause(0.8)
        XCTContext.runActivity(named: "DEMO typing") { _ in
            for word in ["Easier", "to", "talk", "on", "insta,", "I'm", "@sam.walks"] {
                input.typeText(word == "@sam.walks" ? word : word + " ")
                pause(0.18)
            }
        }
        pause(0.9)
        XCTContext.runActivity(named: "DEMO send") { _ in element(app, "blind.chat.send").tap() }
        XCTAssertTrue(element(app, "blind.warning.sheet").waitForExistence(timeout: 10))
        pause(4)
        XCTContext.runActivity(named: "DEMO edit") { _ in element(app, "blind.warning.edit").tap() }
        pause(1.5)
        XCTContext.runActivity(named: "DEMO reveal") { _ in element(app, "blind.chat.reveal").tap() }
        let confirm = element(app, "blind.reveal.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        pause(2.5)
        XCTContext.runActivity(named: "DEMO confirm") { _ in confirm.tap() }
        XCTAssertTrue(element(app, "blind.reveal.close").waitForExistence(timeout: 10))
        pause(5)
    }

    /// Both tapped Reveal: the veil lifts.
    @MainActor
    func testDemo3BlindMutualReveal() {
        let app = launch("chatting", route: "blindChat/\(fox)")
        let reveal = element(app, "blind.chat.reveal")
        XCTAssertTrue(reveal.waitForExistence(timeout: 20))
        pause(2.5)
        XCTContext.runActivity(named: "DEMO reveal") { _ in reveal.tap() }
        let confirm = element(app, "blind.reveal.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        pause(2)
        XCTContext.runActivity(named: "DEMO confirm") { _ in confirm.tap() }
        pause(9)
    }
}
