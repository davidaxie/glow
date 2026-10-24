import SwiftUI

// Owner: B6. Hides something while the screen is recorded, mirrored or sent over AirPlay (P12).
//
//     DeckView(…).glowHiddenWhenCaptured()
//
// It reads SwiftUI's `isSceneCaptured`, so a test or a Debug launch argument can fake a capture
// with `.environment(\.isSceneCaptured, true)`. Logging screenshots is C1's (P12).

extension View {
    /// While the screen is being captured, draws a cover instead of this view. The view isn't
    /// blurred: it isn't drawn at all, so nothing of it can be recovered from a recording. Its size
    /// stays the same, so the layout doesn't jump.
    public func glowHiddenWhenCaptured() -> some View {
        modifier(GlowCaptureShield())
    }
}

struct GlowCaptureShield: ViewModifier {
    @Environment(\.isSceneCaptured) private var isCaptured

    func body(content: Content) -> some View {
        content
            .opacity(isCaptured ? 0 : 1)
            .accessibilityHidden(isCaptured)
            .overlay {
                if isCaptured {
                    GlowCaptureCover()
                }
            }
    }
}

/// What shows in place of hidden content: a soft, blurred-looking wash and a short note.
struct GlowCaptureCover: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.glowSurfaceRaised, .glowSurface, .glowSurfaceRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            VStack(spacing: GlowSpacing.xs) {
                Image(systemName: "eye.slash")
                    .font(.glow(.title))
                Text("Hidden while your screen is shared")
                    .glowFont(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.glowTextSecondary)
            .padding(GlowSpacing.md)
        }
        .accessibilityElement(children: .combine)
    }
}
