import AppCore
import Testing
@testable import FeatureOnboarding

// Placeholder test from A3. Owner: B1.
@MainActor
struct FeatureOnboardingTests {
    @Test func entryViewStartsAtTheGivenStep() {
        #expect(OnboardingFlowView(step: .photos).step == .photos)
    }
}
