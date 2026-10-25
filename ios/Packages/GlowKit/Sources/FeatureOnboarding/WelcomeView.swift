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
/// U1: a breathing light, the wordmark in New York, and the three lines rising in one by one.
struct WelcomeContent: View {
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xl) {
            VStack(alignment: .leading, spacing: 0) {
                GlowBreathingLight()
                    .padding(.leading, -GlowSpacing.xl)
                    .padding(.bottom, -GlowSpacing.xxl)
                GlowWordmark()
                Text("Notice someone. Find out if it's mutual.")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
                    .padding(.top, GlowSpacing.xxs)
            }
            .glowRise(index: 0, isVisible: appeared)

            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                WelcomeLine(
                    systemImage: "hand.tap",
                    text: "Noticed someone across the room? Tap their card. They won't know.",
                )
                .glowRise(index: 2, isVisible: appeared)
                WelcomeLine(
                    systemImage: "heart",
                    text: "If they noticed you too, you both find out at the same moment.",
                )
                .glowRise(index: 3, isVisible: appeared)
                WelcomeLine(
                    systemImage: "lock",
                    text: "Until then, nobody sees your name, your face or where you are.",
                )
                .glowRise(index: 4, isVisible: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}

private struct WelcomeLine: View {
    let systemImage: String
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: GlowSpacing.md) {
            Image(systemName: systemImage)
                .font(.glow(.callout))
                .foregroundStyle(.glowAccent)
                .frame(width: iconSize, height: iconSize)
                .glowGlass(cornerRadius: iconSize / 2)
                .accessibilityHidden(true)
            Text(text)
                .glowFont(.body)
                .foregroundStyle(.glowTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack { WelcomeView {} }
        .preferredColorScheme(.dark)
}
