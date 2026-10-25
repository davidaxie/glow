import XCTest

/// FeatureDeck end to end on a made-up room (C1, cross-owner for D1). Every launch uses Debug-only
/// arguments: `-GlowDebugDeckFixture` swaps in FeatureDeck's fixture room (no network, no real
/// people), `-GlowDebugRoute deck/<room>` opens the deck at launch (C3's DebugRoute, which #39 extends), and
/// `-GlowDebugFakeScreenCapture YES` acts as if the screen is being recorded. D1 owns this folder.
final class DeckUITests: XCTestCase {
    private let room = "de000000-0000-4000-8000-000000000001"
    /// The one card in the 200-person fixture room with the target look (FixtureDeckService).
    private let target = "aaaaaaaa-0000-4000-8000-000000000079"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GlowDebugRoute", "deck/\(room)"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func cards(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'deck.card.'"))
    }

    /// Closes What did you notice and shows everyone.
    @MainActor
    private func showEveryone(_ app: XCUIApplication) {
        let apply = app.buttons["deck.notice.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        apply.tap()
    }

    /// P12: with screen recording faked, the deck is covered, and no card is on screen or reachable.
    @MainActor
    func testTheDeckIsHiddenWhileTheScreenIsRecorded() {
        let app = launch(["-GlowDebugDeckFixture", "24", "-GlowDebugFakeScreenCapture", "YES"])
        showEveryone(app)
        XCTAssertTrue(element(app, "deck.hidden").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Looks are hidden"].exists)
        XCTAssertEqual(cards(app).count, 0, "No card may be on screen while it's recorded")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deck-hidden-while-recorded"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The same room with nothing recording shows its cards, so the test above means something.
    @MainActor
    func testTheDeckShowsCardsWhenNothingIsRecording() {
        let app = launch(["-GlowDebugDeckFixture", "24"])
        showEveryone(app)
        XCTAssertTrue(cards(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "deck.hidden").exists)
    }

    /// The mission: in a room of 200, find the person you noticed with filters and reach That's
    /// them in under 20 seconds.
    @MainActor
    func testFindingOneLookInARoomOfTwoHundredTakesUnderTwentySeconds() {
        let app = launch(["-GlowDebugDeckFixture", "200"])
        XCTAssertTrue(app.buttons["deck.notice.apply"].waitForExistence(timeout: 15))

        let started = Date()
        let picks = [
            ("deck.notice.top", "Green"),
            ("deck.notice.hairLength", "Short"),
            ("deck.notice.hairColor", "Blonde"),
            ("deck.notice.extras", "Glasses"),
        ]
        let apply = app.buttons["deck.notice.apply"]
        for (group, chip) in picks {
            let button = element(app, group).buttons[chip]
            // The apply bar covers the bottom of the sheet: scroll a chip clear of it first.
            if !button.isHittable || button.frame.maxY > apply.frame.minY - 8 {
                element(app, "deck.notice.hairLength").swipeUp()
            }
            button.tap()
            XCTAssertTrue(button.isSelected, "\(chip) should be picked")
        }
        apply.tap()

        let card = element(app, "deck.card.\(target)")
        let found = card.waitForExistence(timeout: 10)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deck-filtered-to-the-target"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(found)
        card.tap()
        let thatsThem = app.buttons["deck.detail.thatsThem"]
        XCTAssertTrue(thatsThem.waitForExistence(timeout: 5))
        thatsThem.tap()
        XCTAssertTrue(element(app, "deck.confirm").waitForExistence(timeout: 5))
        let seconds = Date().timeIntervalSince(started)

        let note = XCTAttachment(string: String(format: "Found the target in a room of 200 in %.1f s", seconds))
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThan(seconds, 20, "Finding the target took \(Int(seconds)) s")
    }
}
