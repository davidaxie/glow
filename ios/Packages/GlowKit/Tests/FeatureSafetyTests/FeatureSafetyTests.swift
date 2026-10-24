import AppCore
import Testing
@testable import FeatureSafety

// Placeholder test from A3. Owner: B8.
@MainActor
struct FeatureSafetyTests {
    @Test func sheetsKeepTheirContext() {
        let context = SafetyContext.card(CardID(rawValue: "00000000-0000-4000-8000-000000000003"))
        #expect(BlockSheet(context: context).context == context)
        #expect(ReportSheet(context: context).context == context)
    }
}
