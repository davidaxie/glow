import APIClient
import DesignSystem
import SwiftUI

// Owner: C1, redrawn by U2 (design wave). One card in the grid, editorial: the photo is the card
// (face-blurred on the phone, watermarked by the server, my own viewer code drawn over it on the
// phone too, C1-D10), with its tags set quietly underneath like a gallery caption, and whether I
// tapped it. No name, distance or anything else about the person. The photo hides while the
// screen is captured (B6-D4, P12).

struct DeckTile: View {
    let card: DeckCard
    /// My viewer code, for the on-device watermark. Nil until my profile is in.
    let viewerCode: String?
    let onUnavailable: @MainActor @Sendable () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeckLight.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            Color.glowSurface
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { DeckCardImage(url: card.imageURL, onUnavailable: onUnavailable) }
                .overlay {
                    if let viewerCode {
                        GlowWatermark(viewerCode)
                    }
                }
                .clipped()
                .glowHiddenWhenCaptured()
                .clipShape(shape)
                .overlay {
                    // The lifted-glass highlight along the top edge.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.glowTextPrimary.opacity(0.18), Color.glowTextPrimary.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom,
                        ),
                        lineWidth: 1,
                    )
                }
                .overlay {
                    if card.tappedByMe {
                        shape.strokeBorder(Color.glowAccent.opacity(0.85), lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if card.tappedByMe {
                        DeckNoticedMark()
                            .padding(GlowSpacing.xs)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .shadow(color: card.tappedByMe ? Color.glowAccent.opacity(0.35) : Color.glowBackground.opacity(0.7), radius: 16, y: 8)
            DeckCaption(tags: card.tags)
                .padding(.horizontal, GlowSpacing.xxs)
        }
        .contentShape(shape)
        .animation(DeckLight.snappy, value: card.tappedByMe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DeckCopy.describe(card.tags)))
        .accessibilityValue(card.tappedByMe ? Text(DeckCopy.noticed) : Text(verbatim: ""))
        .accessibilityAddTraits(card.tappedByMe ? [.isButton, .isSelected] : .isButton)
    }
}

/// The small glass mark on a look I tapped: only I ever see it (P5).
struct DeckNoticedMark: View {
    var body: some View {
        Image(systemName: "sparkle")
            .glowFont(.caption)
            .foregroundStyle(.glowOnAccent)
            .padding(GlowSpacing.xs)
            .background(Circle().fill(Color.glowAccent))
            .shadow(color: Color.glowAccent.opacity(0.6), radius: 8)
            .accessibilityHidden(true)
    }
}

/// A card's tags as a quiet caption under the photo: swatch dots and words, no boxes.
struct DeckCaption: View {
    let tags: CardTags

    var body: some View {
        GlowFlowLayout(spacing: GlowSpacing.sm, rowSpacing: GlowSpacing.xxs) {
            ForEach(DeckTags.glowTags(tags, compact: true), id: \.self) { tag in
                HStack(spacing: 5) {
                    if let swatch = tag.swatch {
                        GlowSwatchDot(swatch)
                            .scaleEffect(0.8)
                    }
                    if let symbol = tag.systemImage {
                        Image(systemName: symbol)
                    }
                    if !tag.title.isEmpty {
                        Text(verbatim: tag.title)
                    }
                }
                .lineLimit(1)
            }
        }
        .glowFont(.caption)
        .foregroundStyle(.glowTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
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
                .padding(.horizontal, GlowSpacing.sm)
                .padding(.vertical, GlowSpacing.xs)
                .background(Color.glowTextPrimary.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.glowTextPrimary.opacity(0.08), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(DeckCopy.describe(tags)))
    }
}
