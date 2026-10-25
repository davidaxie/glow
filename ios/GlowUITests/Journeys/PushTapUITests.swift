import Foundation
import XCTest

/// Taps each push fixture's notification and checks it opens its screen (B5's request, and
/// `RealtimeEvent.destination`). The Mac sends each push, because a UI test can't: the harness
/// (scripts/e2e/harness.ts serve) runs `xcrun simctl push` on request.
///
///     scripts/e2e/run.sh push
final class PushTapUITests: XCTestCase {
    /// Each fixture in ios/fixtures/push/, the module whose screen tapping it must open, and the
    /// words that screen shows. The fixtures' match IDs aren't real, so the match, glow and chat
    /// screens show their "couldn't open" states; that still proves the tap routed there.
    /// The words are a stand-in until each screen has a `screen.<Module>` identifier (HANDOFFS,
    /// For C2, C3 and C4), which wins when present.
    private let destinations: [(fixture: String, module: String, words: [String])] = [
        ("match_created", "FeatureMatch", ["Couldn't open this match", "Someone you noticed noticed you back."]),
        ("match_choice", "FeatureMatch", ["Couldn't open this match"]),
        ("match_recheck", "FeatureMatch", ["Couldn't open this match"]),
        ("match_ended", "FeatureMatch", ["Couldn't load your matches", "Matches"]),
        ("glow_started", "FeatureGlow", ["Something went wrong.", "Couldn't load your matches"]),
        ("glow_ended", "FeatureChat", ["The chat didn't load.", "Chat"]),
        ("message_created", "FeatureChat", ["The chat didn't load.", "Chat"]),
        ("checkin_expiring", "FeatureDeck", []),
        ("deck_changed", "FeatureDeck", []),
    ]

    override func setUp() {
        // Every fixture is checked even when an earlier one fails, so one run lists all of them.
        continueAfterFailure = true
    }

    @MainActor
    func testEveryNotificationOpensItsScreen() async throws {
        let config = try E2EConfig.require(needsPlayerB: false)
        let folder = try XCTUnwrap(config.pushFixtures, "run.sh passes GLOW_E2E_PUSH_DIR")
        let harness = Harness(base: config.harness)
        let personA = GlowA.launch(config, for: self, openRoom: false)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for (fixture, module, words) in destinations {
            let body = try alertBody(URL(fileURLWithPath: folder).appending(path: "\(fixture).apns"))
            // From the background, so it shows as a banner on the springboard.
            XCUIDevice.shared.press(.home)
            try await harness.push(fixture)
            let banner = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 15), "\(fixture): no banner saying \"\(body)\"")
            banner.tap()

            let screen = personA.element(prefix: "screen.\(module)")
            let deadline = Date().addingTimeInterval(15)
            var opened = false
            while !opened, Date() < deadline {
                opened = screen.exists || words.contains { personA.label($0).exists }
                if !opened {
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            personA.attachScreen("push \(fixture)")
            let seen = personA.app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: " | ")
            XCTAssertTrue(opened, "\(fixture): its banner didn't open a \(module) screen. On screen: \(seen)")
        }
    }

    /// The lock screen text a fixture shows (never a name, P6).
    private func alertBody(_ file: URL) throws -> String {
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        let aps = payload?["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        return try XCTUnwrap(alert?["body"] as? String, "\(file.lastPathComponent) has no alert body")
    }
}
