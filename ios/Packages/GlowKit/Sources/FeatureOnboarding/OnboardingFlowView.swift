import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B1.
// Keep `OnboardingFlowView(step:)` public: the app shows it while the session is signed out or
// onboarding. Replace everything inside it.

/// Welcome, sign in, profile, photos and notifications, starting at `step`.
public struct OnboardingFlowView: View {
    public let step: OnboardingStep

    public init(step: OnboardingStep) {
        self.step = step
    }

    public var body: some View {
        NavigationStack {
            PlaceholderScreen(
                "Welcome to Glow",
                module: "FeatureOnboarding",
                owner: "B1",
                details: ["Step: \(step.rawValue)"],
            )
        }
    }
}

#Preview {
    OnboardingFlowView(step: .welcome)
}
