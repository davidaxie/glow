import XCTest

/// Check-in expiry on Glow A: A checks in, the harness ends the check-in as if its 3 hours ran
/// out and runs the purge cron, and the app says so and offers to check in again.
///
///     scripts/e2e/run.sh expiry
final class ExpiryJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAnExpiredCheckInSaysSoAndOffersAnother() async throws {
        let config = try E2EConfig.require(needsPlayerB: false)
        let personA = GlowA.launch(config, for: self)
        personA.joinAndCheckIn()

        try await Harness(base: config.harness).expireCheckIn()

        // The deck refetches when it opens, and the server answers emptyReason checkin_ended.
        personA.tap("room.seeLooks")
        let apply = personA.element("deck.notice.apply")
        if apply.waitForExistence(timeout: 10) { apply.tap() }
        let again = personA.app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["deck.empty.checkInAgain", "room.checkInAgain"])).firstMatch
        personA.expect(again, "Check in again", timeout: 30)
        personA.attachScreen("check-in ended")
    }
}
