import XCTest

/// Y1: Blind mode against a live server, two phones. Each phone runs one step, signed in through the
/// Debug test sign-in, in this order:
///
/// - `a1` on Glow A (person A, not yet in Blind): opt in, like 5 cards, open the drop, say hello,
///   tap Reveal (one-sided: A waits).
/// - `b1` on Glow B (person B, already liked A through the API): open the drop, read A's hello,
///   reply, tap Reveal: both tapped, the reveal screen shows A.
/// - `a2` on Glow A: A reads B's reply and sees the reveal.
///
/// Configured through `TEST_RUNNER_GLOW_BLIND_STEP`, `_EMAIL` and `_SHOTS` (a folder on the Mac for
/// screenshots). Without them it skips, so `scripts/sim.sh test` stays quick.
final class BlindLiveUITests: XCTestCase {
    private struct Config {
        let step: String
        let email: String
        let shots: URL
    }

    private var config: Config!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let step = env["GLOW_BLIND_STEP"], let email = env["GLOW_BLIND_EMAIL"], let shots = env["GLOW_BLIND_SHOTS"] else {
            throw XCTSkip("A live Blind step: run it with TEST_RUNNER_GLOW_BLIND_STEP, _EMAIL and _SHOTS.")
        }
        config = Config(step: step, email: email, shots: URL(fileURLWithPath: shots))
    }

    @MainActor
    func testBlindLiveStep() throws {
        let app = XCUIApplication()
        let route = config.step == "b1" ? "blindDrop" : "blind"
        app.launchArguments += ["-GlowDebugTestLogin", config.email, "-GlowDebugRoute", route]
        if config.step == "a2" {
            app.launchArguments += ["-GlowDebugBlindSection", "chats"]
        }
        app.launch()
        switch config.step {
        case "a1": try stepA1(app)
        case "b1": try stepB1(app)
        case "a2": try stepA2(app)
        default: XCTFail("unknown step \(config.step)")
        }
    }

    // MARK: Steps

    @MainActor
    private func stepA1(_ app: XCUIApplication) throws {
        let join = app.buttons["blind.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 40), "the opt-in screen")
        shot("a-optin")
        join.tap()

        let like = app.buttons["blind.deck.like"]
        XCTAssertTrue(like.waitForExistence(timeout: 20), "the deck after opting in")
        pause(2.5) // the first photo loads through the API
        shot("a-deck")
        // Person B (through the API) likes A once A is a member; the Mac drops a file when done.
        if let go = ProcessInfo.processInfo.environment["GLOW_BLIND_GO"] {
            let deadline = Date().addingTimeInterval(90)
            while !FileManager.default.fileExists(atPath: go), Date() < deadline {
                pause(0.5)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: go), "person B liked A")
        }
        // Like every card (at least 5), so B's card is among them whatever the deck's order.
        var likes = 0
        while likes < 10, !app.descendants(matching: .any)["blind.deck.empty"].exists {
            guard waitHittable(like, timeout: 8) else { break }
            like.tap()
            likes += 1
            pause(1.5)
        }
        XCTAssertGreaterThanOrEqual(likes, 5, "five right swipes")
        let openDrop = app.buttons["blind.deck.openDrop"]
        XCTAssertTrue(openDrop.waitForExistence(timeout: 20), "Open your drop after 5 likes")
        shot("a-deck-drop-ready")
        openDrop.tap()

        let open = app.buttons["blind.drop.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "the drop's open button (demo mode)")
        shot("a-drop-ready")
        open.tap()
        let seeChats = app.buttons["blind.drop.seeChats"]
        XCTAssertTrue(seeChats.waitForExistence(timeout: 30), "the opened drop")
        shot("a-drop-opened")
        seeChats.tap()

        openFirstChat(app, who: "a")
        send("Hello from the other side of the room", in: app)
        shot("a-chat-sent")

        tapReveal(app)
        pause(1.5)
        shot("a-reveal-waiting")
        XCTAssertFalse(app.otherElements["blind.reveal.screen"].exists, "a one-sided reveal never reveals")
    }

    @MainActor
    private func stepB1(_ app: XCUIApplication) throws {
        let open = app.buttons["blind.drop.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 40), "B's drop is ready")
        shot("b-drop-ready")
        open.tap()
        let seeChats = app.buttons["blind.drop.seeChats"]
        XCTAssertTrue(seeChats.waitForExistence(timeout: 30), "B's opened drop")
        shot("b-drop-opened")
        seeChats.tap()

        openFirstChat(app, who: "b")
        XCTAssertTrue(text(containing: "Hello from the other side", in: app).waitForExistence(timeout: 20), "A's message reaches B")
        // One-sided: A tapped Reveal, and nothing on B's screen says so.
        XCTAssertFalse(app.otherElements["blind.reveal.screen"].exists)
        shot("b-chat-before-reveal")

        send("Hi! Guess we both swiped right", in: app)
        shot("b-chat-replied")

        tapReveal(app)
        let screen = app.descendants(matching: .any)["blind.reveal.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20), "both tapped: the reveal screen")
        pause(3) // the veil lifts over 1.2 s, the name sets in, the photos settle
        shot("b-revealed")
    }

    @MainActor
    private func stepA2(_ app: XCUIApplication) throws {
        openFirstChat(app, who: "a2")
        XCTAssertTrue(text(containing: "Guess we both swiped right", in: app).waitForExistence(timeout: 20), "B's reply reaches A")
        pause(2)
        shot("a-chat-revealed")
        let screen = app.descendants(matching: .any)["blind.reveal.screen"]
        if !screen.exists {
            let reveal = app.descendants(matching: .any)["blind.chat.reveal"]
            if reveal.exists, reveal.isHittable {
                reveal.tap()
            }
        }
        if screen.waitForExistence(timeout: 10) {
            pause(3)
        }
        shot("a-revealed")
    }

    // MARK: Helpers

    @MainActor
    private func openFirstChat(_ app: XCUIApplication, who: String) {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'blind.chats.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "a chat in the list")
        pause(1)
        shot("\(who)-chats")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["blind.chat.input"].waitForExistence(timeout: 20), "the chat")
    }

    @MainActor
    private func send(_ message: String, in app: XCUIApplication) {
        let input = app.descendants(matching: .any)["blind.chat.input"]
        input.tap()
        input.typeText(message)
        app.buttons["blind.chat.send"].tap()
        let warning = app.buttons["blind.warning.send"]
        if warning.waitForExistence(timeout: 3) {
            shot("warning-sheet")
            warning.tap()
        }
        XCTAssertTrue(text(containing: String(message.prefix(20)), in: app).waitForExistence(timeout: 15), "the sent message shows")
    }

    @MainActor
    private func tapReveal(_ app: XCUIApplication) {
        let reveal = app.descendants(matching: .any)["blind.chat.reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "the reveal pill")
        reveal.tap()
        let confirm = app.buttons["blind.reveal.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the reveal sheet")
        shot("\(config.step.prefix(1))-reveal-sheet")
        confirm.tap()
    }

    @MainActor
    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    @MainActor
    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.isHittable {
                return true
            }
            pause(0.3)
        }
        return false
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: config.shots, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: config.shots.appendingPathComponent("blind-live-\(name).png"))
    }
}
