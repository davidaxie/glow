import Foundation
import XCTest

/// Taps each push fixture's notification and checks it opens its screen (B5's request, and
/// `RealtimeEvent.destination`). The Mac sends each push, because a UI test can't: the harness
/// (scripts/e2e/harness.ts serve) runs `xcrun simctl push` on request.
///
///     scripts/e2e/run.sh push
final class PushTapUITests: XCTestCase {
    /// Each fixture in ios/fixtures/push/ and the module whose screen tapping it must open.
    private let destinations: [(fixture: String, module: String)] = [
        ("match_created", "FeatureMatch"),
        ("match_choice", "FeatureMatch"),
        ("match_recheck", "FeatureMatch"),
        ("match_ended", "FeatureMatch"),
        ("glow_started", "FeatureGlow"),
        ("glow_ended", "FeatureChat"),
        ("message_created", "FeatureChat"),
        ("checkin_expiring", "FeatureDeck"),
        ("deck_changed", "FeatureDeck"),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryNotificationOpensItsScreen() async throws {
        let config = try E2EConfig.require(needsPlayerB: false)
        let folder = try XCTUnwrap(config.pushFixtures, "run.sh passes GLOW_E2E_PUSH_DIR")
        let harness = Harness(base: config.harness)
        let personA = GlowA.launch(config, for: self, openRoom: false)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for (fixture, module) in destinations {
            let body = try alertBody(URL(fileURLWithPath: folder).appending(path: "\(fixture).apns"))
            // From the background, so it shows as a banner on the springboard.
            XCUIDevice.shared.press(.home)
            try await harness.push(fixture)
            let banner = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 15), "\(fixture): no banner saying \"\(body)\"")
            banner.tap()

            let screen = personA.element(prefix: "screen.\(module)")
            let opened = screen.waitForExistence(timeout: 15)
            personA.attachScreen("push \(fixture)")
            XCTAssertTrue(opened, "\(fixture): its banner didn't open a \(module) screen")
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
