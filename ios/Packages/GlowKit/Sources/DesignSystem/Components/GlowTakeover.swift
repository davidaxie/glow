import SwiftUI

// Owner: B6. A full-screen takeover, like the mutual moment.
//
//     GlowTakeover(.bloom) {
//         VStack(spacing: GlowSpacing.lg) {
//             Text("Someone you noticed noticed you back.").glowFont(.display)
//             Button("See who") { … }.buttonStyle(.glowPrimary)
//         }
//     } onClose: {
//         dismiss()
//     }
//
// The content arrives with the reveal spring (a plain fade under Reduce Motion).

/// What's behind a takeover.
public enum GlowBackdrop: Sendable, Equatable {
    /// The plain app background.
    case night
    /// The app background with a soft accent glow rising from below. For the mutual moment.
    case bloom
    /// A glow color. Content gets the color's ink.
    case hue(GlowHue)

    /// The accent's strength at the brightest point of the bloom. Text over it keeps AA
    /// (`GlowPalette.textPairings`).
    static let bloomOpacity = 0.45
}

public struct GlowTakeover<Content: View>: View {
    public typealias Backdrop = GlowBackdrop

    private let backdrop: Backdrop
    private let onClose: (() -> Void)?
    private let content: Content
    private let startsRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    /// - Parameter onClose: shows a close button in the top corner when set.
    public init(_ backdrop: Backdrop = .bloom, @ViewBuilder content: () -> Content, onClose: (() -> Void)? = nil) {
        self.init(backdrop, startsRevealed: false, content: content, onClose: onClose)
    }

    /// `startsRevealed` skips the entrance, for the Gallery and snapshot tests.
    init(_ backdrop: Backdrop, startsRevealed: Bool, @ViewBuilder content: () -> Content, onClose: (() -> Void)?) {
        self.backdrop = backdrop
        self.onClose = onClose
        self.startsRevealed = startsRevealed
        self.content = content()
    }

    public var body: some View {
        let shown = isRevealed || startsRevealed
        ZStack {
            GlowBackdropView(backdrop: backdrop)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content
                .foregroundStyle(foreground)
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.vertical, GlowSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown || reduceMotion ? 1 : 0.92)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.glow(.headline))
                        .foregroundStyle(foreground)
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                        .background(closeFill, in: Circle())
                }
                .accessibilityLabel(Text("Close"))
                .padding(GlowSpacing.md)
            }
        }
        .environment(\.glowHue, hue)
        .onAppear {
            withAnimation(GlowMotion.animation(.reveal, reduceMotion: reduceMotion)) {
                isRevealed = true
            }
        }
    }

    /// The glow color behind the content, so `.glowOnSurface` buttons work here too.
    private var hue: GlowHue? {
        if case let .hue(hue) = backdrop {
            return hue
        }
        return nil
    }

    private var foreground: Color {
        if case let .hue(hue) = backdrop {
            return hue.ink.color
        }
        return .glowTextPrimary
    }

    private var closeFill: Color {
        if case let .hue(hue) = backdrop {
            return hue.ink.color.opacity(0.12)
        }
        return .glowSurfaceRaised
    }
}

struct GlowBackdropView: View {
    let backdrop: GlowBackdrop

    var body: some View {
        switch backdrop {
        case .night:
            Color.glowBackground
        case .bloom:
            ZStack {
                Color.glowBackground
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [.glowAccent.opacity(GlowBackdrop.bloomOpacity), .glowAccent.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 1.05),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.8,
                    )
                }
            }
        case let .hue(hue):
            hue.color
        }
    }
}
