import XCTest

/// The chat path on Glow A, with person B played by scripts/e2e/player-b.ts: mutual, Just chat,
/// then a message each way.
///
///     scripts/e2e/run.sh chat
final class ChatJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testJustChatThenAMessageEachWay() async throws {
        let config = try E2EConfig.require()
        let personB = try PlayerB(base: XCTUnwrap(config.playerB))
        let personA = try await GlowA.matched(config, with: personB, for: self)

        personA.choose("Just chat")
        let chose = try await personB.run("chat")
        XCTAssertEqual(chose.step, "chose-chat:chat")

        let fromB = "Hi, I'm by the window."
        try await personB.run("say", text: fromB)
        personA.expect(personA.label(fromB), "B's message in A's chat", timeout: 30)

        let fromA = "On my way over."
        personA.say(fromA)
        let read = try await personB.run("read", text: fromA)
        XCTAssertEqual(read.messages, ["B: \(fromB)", "A: \(fromA)"])
        personA.attachScreen("chat")
    }
}

extension GlowA {
    /// Launches, checks in, and gets to the mutual moment with person B, who taps first.
    static func matched(_ config: E2EConfig, with personB: PlayerB, for test: XCTestCase) async throws -> GlowA {
        let personA = launch(config, for: test)
        personA.joinAndCheckIn()
        try await personB.run("tap")
        personA.tapTheOnlyCard()
        personA.expectMutual()
        try await personB.run("match")
        return personA
    }
}
