import AppCore
import Testing
@testable import FeatureChat

// Placeholder test from A3. Owner: C4.
@MainActor
struct FeatureChatTests {
    @Test func entryViewKeepsTheMatch() {
        let match = MatchID(rawValue: "00000000-0000-4000-8000-000000000001")
        #expect(ChatView(matchID: match).matchID == match)
    }
}
