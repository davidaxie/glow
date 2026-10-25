import XCTest

/// Person A on Glow A: launches the app signed in as A and walks the screens, by the identifiers
/// and words each owner published in docs/HANDOFFS.md.
@MainActor
struct GlowA {
    let app: XCUIApplication
    let test: XCTestCase

    /// Launches signed in as person A (B1's Debug test sign-in), opening the run's room link as if
    /// its QR code was scanned, with B3's "Use test photo" button for the check-in.
    static func launch(_ config: E2EConfig, for test: XCTestCase, openRoom: Bool = true) -> GlowA {
        let app = XCUIApplication()
        app.launchArguments += ["-GlowDebugTestLogin", config.emailA, "-GlowDebugCheckInPhoto", config.photo]
        if openRoom {
            app.launchArguments += ["-GlowDebugOpenURL", config.roomLink]
        }
        // The location prompt, if `simctl privacy grant` didn't already answer it.
        test.addUIInterruptionMonitor(withDescription: "Location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        return GlowA(app: app, test: test)
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The first element whose identifier starts with `prefix`.
    func element(prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// The first text or button whose label contains `text`, ignoring case.
    func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Waits for `target`, attaching the screen and failing the test if it never shows.
    @discardableResult
    func expect(
        _ target: XCUIElement,
        _ what: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) -> XCUIElement {
        if !target.waitForExistence(timeout: timeout) {
            attachScreen("missing \(what)")
            XCTFail("\(what) never appeared", file: file, line: line)
        }
        return target
    }

    func tap(_ target: XCUIElement, _ what: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        expect(target, what, timeout: timeout, file: file, line: line)
        if !target.isHittable {
            app.swipeUp()
        }
        target.tap()
    }

    func tap(_ identifier: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        tap(element(identifier), identifier, timeout: timeout, file: file, line: line)
    }

    /// Lets an entrance finish before a screenshot: since the redesign (U3) the glow's code word and
    /// We met rise in over about 1.5 s after the color fills the screen, and they're already in the
    /// accessibility tree (at opacity 0) while they rise.
    func settle(for seconds: TimeInterval = 2.5) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "the entrance settles")], timeout: seconds)
    }

    func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }

    // MARK: - Steps every journey shares

    /// B2's join passes the location check (`sim.sh at venue` stands inside the room), then B3's
    /// check-in with the test photo and a top color, then C1's room home.
    func joinAndCheckIn(top: String = "white") {
        tap("checkin.debugPhoto", timeout: 40)
        tap("checkin.usePhoto")
        tap("checkin.top.\(top)")
        tap("checkin.submit")
        expect(element("screen.FeatureDeck.roomHome"), "the room home after checking in", timeout: 30)
        attachScreen("checked in")
    }

    /// C1's deck: everyone, person B's card (the only other one in the run's room), That's them,
    /// then the tap.
    func tapTheOnlyCard() {
        tap("room.seeLooks")
        tap("deck.notice.apply")
        let card = expect(element(prefix: "deck.card."), "person B's card in the deck", timeout: 30)
        attachScreen("deck")
        card.tap()
        tap("deck.detail.thatsThem")
        expect(element("deck.confirm.tap"), "deck.confirm.tap")
        attachScreen("confirm tap")
        tap("deck.confirm.tap")
    }

    /// C2's mutual takeover, after a tap that answered mutual.
    func expectMutual() {
        expect(label("Someone you noticed noticed you back."), "the mutual moment", timeout: 30)
        attachScreen("mutual")
    }

    func choose(_ button: String) {
        tap(app.buttons[button], "the \(button) button")
    }

    /// C4's chat: types and sends a message.
    func say(_ text: String) {
        let field = app.textFields["Message"].exists ? app.textFields["Message"] : app.textViews["Message"]
        tap(field, "the message field", timeout: 30)
        field.typeText(text)
        tap(app.buttons["Send"], "Send")
    }
}
