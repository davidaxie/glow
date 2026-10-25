import XCTest

/// The block path on Glow A, with person B played by scripts/e2e/player-b.ts: mutual, chat, then
/// A blocks B from the chat menu. B's match and chat are gone within seconds (P7).
///
///     scripts/e2e/run.sh block
final class BlockJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBlockingFromTheChatEndsItForBoth() async throws {
        let config = try E2EConfig.require()
        let personB = try PlayerB(base: XCTUnwrap(config.playerB))
        let personA = try await GlowA.matched(config, with: personB, for: self)

        personA.choose("Just chat")
        try await personB.run("chat")
        try await personB.run("say", text: "Hello?")
        personA.expect(personA.label("Hello?"), "B's message", timeout: 30)

        // C4's chat menu, then B8's block sheet.
        personA.tap(personA.app.buttons["Chat options"], "the chat menu")
        personA.tap(personA.app.buttons["Block"].firstMatch, "Block in the menu")
        personA.tap(personA.app.buttons["Block"].firstMatch, "Block in the sheet")
        personA.expect(personA.label("They won't see you again."), "the block confirmation")
        personA.attachScreen("blocked")
        personA.tap(personA.app.buttons["Close"], "Close")

        // B: the match is gone from the list and its ID answers 404, inside player B's timeout.
        let ended = try await personB.run("ended")
        XCTAssertEqual(ended.step, "ended")
    }
}
