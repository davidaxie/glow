import AppCore
import DesignSystem
import SwiftUI

// Owner: X2. Pieces of the Blind deck: stamps, buttons, drop marks and the cap shake.

/// Pass, Like or Love, fading in as the card is dragged.
struct BlindSwipeStamp: View {
    let kind: BlindSwipeKind
    let strength: Double

    var body: some View {
        Label(title, systemImage: symbol)
            .glowFont(.headline)
            .foregroundStyle(kind == .pass ? .glowTextPrimary : .glowAccent)
            .padding(.horizontal, GlowSpacing.md)
            .padding(.vertical, GlowSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .pass ? .glowTextPrimary : .glowAccent, lineWidth: 2))
            .opacity(strength)
            .scaleEffect(0.9 + 0.1 * strength)
            .accessibilityHidden(true)
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .pass: "Pass"
        case .like: "Like"
        case .love: "Love"
        }
    }

    private var symbol: String {
        switch kind {
        case .pass: "xmark"
        case .like: "heart"
        case .love: "heart.fill"
        }
    }
}

/// Pass, Love and Like. Right-swipe buttons dim when none are left but stay tappable, so pressing
/// one explains why.
struct BlindSwipeButtons: View {
    let canSwipeRight: Bool
    let isEnabled: Bool
    let action: (BlindSwipeKind) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: GlowSpacing.xl) {
            round(.pass, symbol: "xmark", title: "Pass", size: 60, filled: false)
            round(.love, symbol: "heart.fill", title: "Love", size: 72, filled: true)
                .opacity(canSwipeRight ? 1 : 0.4)
            round(.like, symbol: "heart", title: "Like", size: 60, filled: false)
                .opacity(canSwipeRight ? 1 : 0.4)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }

    private func round(_ kind: BlindSwipeKind, symbol: String, title: LocalizedStringKey, size: CGFloat, filled: Bool) -> some View {
        Button {
            action(kind)
        } label: {
            VStack(spacing: GlowSpacing.xxs) {
                Image(systemName: symbol)
                    .glowFont(filled ? .title : .headline)
                    .foregroundStyle(filled ? .glowOnAccent : (kind == .pass ? .glowTextPrimary : .glowAccent))
                    .frame(width: size, height: size)
                    .background(filled ? .glowAccent : .glowSurfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(filled ? .glowClear : .glowLine, lineWidth: 1))
                Text(title).glowFont(.caption).foregroundStyle(.glowTextSecondary)
            }
        }
        .buttonStyle(BlindPressStyle())
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("blind.deck.\(kind.rawValue)")
    }
}

struct BlindPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(BlindMotion.snappy, value: configuration.isPressed)
    }
}

/// Five marks toward opening the drop.
struct BlindDropMarks: View {
    let filled: Int

    var body: some View {
        HStack(spacing: GlowSpacing.xs) {
            ForEach(0 ..< BlindDeckRules.dropMinimum, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? .glowAccent : .glowSurfaceRaised)
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(filled) of \(BlindDeckRules.dropMinimum) right swipes toward your drop"))
    }
}

/// A horizontal shake driven by an incrementing counter.
struct BlindShake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
    }
}
