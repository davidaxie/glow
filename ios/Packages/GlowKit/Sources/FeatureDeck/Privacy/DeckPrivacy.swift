import DesignSystem
import SwiftUI
import UIKit

// Owner: C1. P12: the deck is hidden while the screen is recorded, mirrored or sent over AirPlay, and
// screenshots of it get a gentle note and a report to `/api/abuse/capture` (B8).
//
// The capture state is SwiftUI's `isSceneCaptured` (iOS 17), so tests and the Debug launch argument
// `-GlowDebugFakeScreenCapture YES` fake a recording with `.environment(\.isSceneCaptured, true)`.
// B6's `.glowHiddenWhenCaptured()` (PR #24) does the same per photo; the deck also covers the whole
// screen, so tags and the layout don't show either.

extension View {
    /// Covers the deck while the screen is captured (or the app isn't active, C1-D4), and tells the
    /// model when a capture starts or a screenshot is taken.
    func deckPrivacy(_ model: DeckModel) -> some View {
        modifier(DeckPrivacyModifier(model: model))
    }

    /// Hides this content (it isn't drawn at all, so nothing can be recovered from a recording) and
    /// puts the privacy cover in its place.
    func deckHidden(_ hidden: Bool) -> some View {
        modifier(DeckHiddenModifier(hidden: hidden))
    }
}

struct DeckPrivacyModifier: ViewModifier {
    let model: DeckModel

    @Environment(\.isSceneCaptured) private var isCaptured
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.deckHidesWhenInactive) private var hidesWhenInactive

    func body(content: Content) -> some View {
        content
            .deckHidden(isCaptured || (hidesWhenInactive && scenePhase != .active))
            .onChange(of: isCaptured, initial: true) { _, captured in
                model.captureChanged(isCaptured: captured)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                model.screenshotTaken()
            }
    }
}

struct DeckHiddenModifier: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden ? 40 : 0)
            .accessibilityHidden(hidden)
            .allowsHitTesting(!hidden)
            .overlay {
                if hidden {
                    DeckPrivacyCover()
                        .transition(.opacity)
                }
            }
    }
}

/// What shows instead of the deck while it's hidden.
struct DeckPrivacyCover: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.glowSurfaceRaised, .glowBackground, .glowSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()
            VStack(spacing: GlowSpacing.sm) {
                Image(systemName: "eye.slash")
                    .font(.glow(.title))
                    .foregroundStyle(.glowAccent)
                    .accessibilityHidden(true)
                Text(DeckCopy.hiddenTitle)
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Text(DeckCopy.hiddenMessage)
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(GlowSpacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deck.hidden")
    }
}
