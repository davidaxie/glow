import DesignSystem
import SwiftUI

/// The first screen: Glow in three short lines, the last one the privacy promise.
struct WelcomeView: View {
    let getStarted: () -> Void

    var body: some View {
        OnboardingScreen(identifier: "onboarding.welcome") {
            WelcomeContent()
        } actions: {
            Button("Get started", action: getStarted)
                .buttonStyle(.glowPrimary)
                .accessibilityIdentifier("onboarding.getStarted")
            Text("Glow is for people 18 and older.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The welcome screen's words, on their own so snapshots show all of them at any text size.
struct WelcomeContent: View {
    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xl) {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: markSize, height: markSize)
                    .foregroundStyle(.glowAccent)
                    .accessibilityHidden(true)
                Text("Glow")
                    .glowFont(.display)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.top, GlowSpacing.xl)

            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                WelcomeLine(
                    systemImage: "hand.tap",
                    text: "Noticed someone across the room? Tap their card. They won't know.",
                )
                WelcomeLine(
                    systemImage: "heart",
                    text: "If they noticed you too, you both find out at the same moment.",
                )
                WelcomeLine(
                    systemImage: "lock",
                    text: "Until then, nobody sees your name, your face or where you are.",
                )
            }
        }
    }
}

private struct WelcomeLine: View {
    let systemImage: String
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.glowAccent)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .glowFont(.body)
                .foregroundStyle(.glowTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { WelcomeView {} }
        .preferredColorScheme(.dark)
}
