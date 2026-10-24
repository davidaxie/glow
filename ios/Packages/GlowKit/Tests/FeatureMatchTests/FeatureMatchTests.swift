import AppCore
import Testing
@testable import FeatureMatch

// Placeholder test from A3. Owner: C2.
@MainActor
struct FeatureMatchTests {
    @Test func entryViewsKeepTheMatch() {
        #expect(MutualMomentView(matchID: .placeholder).matchID == .placeholder)
        #expect(MatchView(matchID: .placeholder).matchID == .placeholder)
    }
}
