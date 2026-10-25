import AppCore
import DesignSystem
import SwiftUI

// Owner: X2. A codename card in the opened drop.

/// One codename card: frosted glass face down, the codename face up.
struct BlindCodenameCard: View {
    let name: String
    let isTurned: Bool
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            back.opacity(isTurned ? 0 : 1)
            front
                .opacity(isTurned ? 1 : 0)
                // The front is drawn mirrored so it reads correctly once the card has turned.
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .rotation3DEffect(.degrees(isTurned && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .blindGlass(cornerRadius: 24, highlighted: isTurned)
        .onChange(of: isTurned) { _, turned in
            guard turned, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.2)) { shimmer = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isTurned ? Text("\(name). New chat.") : Text("A new chat, about to turn over"))
        .accessibilityHidden(!isTurned)
        .accessibilityIdentifier("blind.drop.card.\(name)")
    }

    private var back: some View {
        HStack(spacing: GlowSpacing.md) {
            BlindVeilOrb(seed: name, size: 44, drifts: false)
            Capsule().fill(.glowSurfaceRaised).frame(width: 110, height: 12)
            Spacer()
        }
        .padding(.horizontal, GlowSpacing.md)
        .blur(radius: 2)
    }

    private var front: some View {
        HStack(spacing: GlowSpacing.md) {
            BlindVeilOrb(seed: name, size: 44)
            VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                Text(name)
                    .font(BlindType.codenameItalic)
                    .foregroundStyle(.glowTextPrimary)
                    .overlay { shimmerBand.mask(Text(name).font(BlindType.codenameItalic)) }
                Text("New chat").glowFont(.caption).foregroundStyle(.glowTextSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, GlowSpacing.md)
    }

    /// A band of light that sweeps across the codename once.
    private var shimmerBand: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.glowAccent.opacity(0), .glowAccent.opacity(0.9), .glowAccent.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing,
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: shimmer ? proxy.size.width * 1.2 : -proxy.size.width * 0.8)
        }
        .allowsHitTesting(false)
    }
}
