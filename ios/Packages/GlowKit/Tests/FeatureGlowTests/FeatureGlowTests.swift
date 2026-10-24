import AppCore
import Testing
@testable import FeatureGlow

// Placeholder test from A3. Owner: C3.
@MainActor
struct FeatureGlowTests {
    @Test func entryViewKeepsTheMatch() {
        let match = MatchID(rawValue: "00000000-0000-4000-8000-000000000001")
        #expect(GlowView(matchID: match).matchID == match)
    }
}
