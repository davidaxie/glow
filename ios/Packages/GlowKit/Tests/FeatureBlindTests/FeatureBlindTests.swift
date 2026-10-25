import AppCore
import Testing
@testable import FeatureBlind

/// Placeholder so the target builds; the rule tests live in BlindRulesTests.swift.
struct FeatureBlindSmokeTests {
    @Test func moduleLoads() {
        #expect(BlindRulesConstants.dailyRightLimit == 20)
    }
}
