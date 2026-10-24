import APIClient
import DesignSystem
import SwiftUI

// Owner: C1. One card in the grid, drawn with B6's `GlowCardTile`: the photo (face-blurred on the
// phone, watermarked by the server), my own viewer code drawn over it on the phone too (C1-D10),
// its tags, and whether I tapped it. No name, distance or anything else about the person. The tile
// hides its photo while the screen is captured (B6-D4, P12).

struct DeckTile: View {
    let card: DeckCard
    /// My viewer code, for the on-device watermark. Nil until my profile is in.
    let viewerCode: String?
    let onUnavailable: @MainActor @Sendable () -> Void

    var body: some View {
        GlowCardTile(
            phase: .ready,
            tags: DeckTags.glowTags(card.tags, compact: true),
            isNoticed: card.tappedByMe,
            accessibilityLabel: Text(DeckCopy.describe(card.tags)),
        ) {
            DeckCardImage(url: card.imageURL, onUnavailable: onUnavailable)
        } watermark: {
            if let viewerCode {
                GlowWatermark(viewerCode)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
        .accessibilityAddTraits(.isButton)
    }
}

/// A card's tags as B6's `GlowTag`s: top color, hair, extras.
enum DeckTags {
    static func glowTags(_ tags: CardTags, compact: Bool = false) -> [GlowTag] {
        var out = [GlowTag(DeckCopy.name(tags.topColor), swatch: GlowSwatch(rawValue: tags.topColor.rawValue))]
        if let hair = hairTitle(tags) {
            out.append(GlowTag(hair, swatch: tags.hairColor.flatMap { GlowSwatch(rawValue: $0.rawValue) }))
        }
        for extra in CardExtra.allCases where tags.extras.contains(extra) {
            if compact, let symbol = extra.deckSymbol {
                out.append(GlowTag("", systemImage: symbol))
            } else {
                out.append(GlowTag(DeckCopy.name(extra), systemImage: extra.deckSymbol))
            }
        }
        return out
    }

    static func hairTitle(_ tags: CardTags) -> String? {
        switch (tags.hairLength, tags.hairColor) {
        case let (length?, color?): "\(DeckCopy.name(length)) \(DeckCopy.name(color).lowercased())"
        case let (length?, nil): DeckCopy.name(length)
        case let (nil, color?): DeckCopy.name(color)
        case (nil, nil): nil
        }
    }
}

/// A card's tags as a wrapping row of small labels, for the enlarged card and the confirm panel.
struct DeckTagRow: View {
    let tags: CardTags

    var body: some View {
        GlowFlowLayout(spacing: GlowSpacing.xxs, rowSpacing: GlowSpacing.xxs) {
            ForEach(DeckTags.glowTags(tags), id: \.self) { tag in
                HStack(spacing: GlowSpacing.xxs) {
                    if let swatch = tag.swatch {
                        GlowSwatchDot(swatch)
                    }
                    if let symbol = tag.systemImage {
                        Image(systemName: symbol)
                    }
                    Text(verbatim: tag.title)
                }
                .glowFont(.caption)
                .foregroundStyle(.glowTextPrimary)
                .lineLimit(1)
                .padding(.horizontal, GlowSpacing.xs)
                .padding(.vertical, GlowSpacing.xxs)
                .background(.glowSurfaceRaised, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DeckCopy.describe(tags)))
    }
}
