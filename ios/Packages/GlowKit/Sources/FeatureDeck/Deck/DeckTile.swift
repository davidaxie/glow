import APIClient
import DesignSystem
import SwiftUI

// Owner: C1. One card in the grid: the photo (face-blurred on the phone and watermarked by the
// server), its tags, and whether I tapped it. No name, distance or anything else about the person.

struct DeckTile: View {
    let card: DeckCard
    let onUnavailable: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Color.glowSurfaceRaised
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    DeckCardImage(url: card.imageURL, onUnavailable: onUnavailable)
                }
                .clipped()
            DeckTagRow(tags: card.tags, compact: true)
                .padding(GlowSpacing.xs)
        }
        .background(.glowSurface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(card.tappedByMe ? AnyShapeStyle(.glowAccent) : AnyShapeStyle(.glowLine), lineWidth: card.tappedByMe ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if card.tappedByMe {
                Label(DeckCopy.noticedBadge, systemImage: "checkmark")
                    .glowFont(.caption)
                    .foregroundStyle(.glowOnAccent)
                    .padding(.horizontal, GlowSpacing.xs)
                    .padding(.vertical, GlowSpacing.xxs)
                    .background(.glowAccent, in: Capsule())
                    .padding(GlowSpacing.xs)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DeckCopy.describe(card.tags)))
        .accessibilityValue(card.tappedByMe ? Text(DeckCopy.noticedBadge) : Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// A card's tags as small, quiet labels: top color, hair, extras.
struct DeckTagRow: View {
    let tags: CardTags
    var compact = false

    var body: some View {
        GlowFlowLayout(spacing: GlowSpacing.xxs, rowSpacing: GlowSpacing.xxs) {
            DeckTagLabel(title: DeckCopy.name(tags.topColor), swatch: GlowSwatch(rawValue: tags.topColor.rawValue))
            if let hair = hairTitle {
                DeckTagLabel(title: hair, swatch: tags.hairColor.flatMap { GlowSwatch(rawValue: $0.rawValue) })
            }
            ForEach(CardExtra.allCases.filter(tags.extras.contains), id: \.self) { extra in
                if compact, let symbol = extra.deckSymbol {
                    DeckTagLabel(title: nil, systemImage: symbol)
                } else {
                    DeckTagLabel(title: DeckCopy.name(extra), systemImage: extra.deckSymbol)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DeckCopy.describe(tags)))
    }

    private var hairTitle: String? {
        switch (tags.hairLength, tags.hairColor) {
        case let (length?, color?): "\(DeckCopy.name(length)) \(DeckCopy.name(color).lowercased())"
        case let (length?, nil): DeckCopy.name(length)
        case let (nil, color?): DeckCopy.name(color)
        case (nil, nil): nil
        }
    }
}

struct DeckTagLabel: View {
    let title: String?
    var swatch: GlowSwatch?
    var systemImage: String?

    var body: some View {
        HStack(spacing: GlowSpacing.xxs) {
            if let swatch {
                GlowSwatchDot(swatch)
            }
            if let systemImage {
                Image(systemName: systemImage)
            }
            if let title {
                Text(verbatim: title)
            }
        }
        .glowFont(.caption)
        .foregroundStyle(.glowTextPrimary)
        .lineLimit(1)
        .padding(.horizontal, GlowSpacing.xs)
        .padding(.vertical, GlowSpacing.xxs)
        .background(.glowSurfaceRaised, in: Capsule())
    }
}
