import XCTest

/// The whole loop on Glow A, with person B played by scripts/e2e/player-b.ts:
/// check in, tap, it's mutual, both choose Find, the same glow on both phones, We met.
///
///     scripts/e2e/run.sh full
final class FullLoopJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFromCheckInToWeMet() async throws {
        let config = try E2EConfig.require()
        let personB = try PlayerB(base: XCTUnwrap(config.playerB))
        let personA = GlowA.launch(config, for: self)

        personA.joinAndCheckIn()

        // B taps A first. It's secret (P5): B's reply says only "sent", and A is told nothing.
        let tapped = try await personB.run("tap")
        XCTAssertEqual(tapped.step, "tapped")
        // A's tap lands second, so A's own reply is mutual and the takeover opens at once.
        personA.tapTheOnlyCard()
        personA.expectMutual()
        try await personB.run("match")

        // Find only happens if both pick it.
        personA.choose("Find each other")
        try await personB.run("find")
        let glowing = try await personB.run("glow")
        let glow = try XCTUnwrap(glowing.glow, "person B has no glow")

        // The same code word on both phones (and the same color, by the same glow ID).
        personA.expect(personA.label(glow.codeWord), "the code word \(glow.codeWord)", timeout: 30)
        personA.attachScreen("glowing \(glow.color)")

        personA.tap(personA.app.buttons["We met"], "We met")
        try await personB.run("met")
        let met = try await personB.run("metboth")
        XCTAssertEqual(met.glow?.status, "met")
        personA.attachScreen("we met")
    }
}
