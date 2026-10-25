import AppCore
import DesignSystem
import SwiftUI

// Owner: C4 (CHIPS-D1, added with David's approval). Icebreaker chips: up to three tap-to-fill
// openers in an empty chat, which exists only after a mutual match and a choice.
//
// They are static text. Tapping one puts it in the composer and nothing else: the person can
// change it, and what they send goes through the normal path like any typed text, with nothing
// that marks it as a chip. The only things filled in are the room's name, the glow's code word and
// the meeting spot, all of which both people already see. A chip whose piece is missing is left
// out rather than shown with a hole.

/// One of the chat's three openers. The raw value is the chip's ID, the only thing analytics get.
enum ChatIcebreaker: String, CaseIterable, Identifiable, Sendable {
    case room
    case word
    case spot

    var id: String {
        rawValue
    }

    /// What the chip says, or nil when a piece it needs is missing.
    func text(roomName: String?, codeWord: String?, meetingSpot: String?) -> String? {
        switch self {
        case .room:
            guard let room = Self.filled(roomName) else { return nil }
            return String(localized: "Hey, glad we both noticed. What brought you to \(room)?")
        case .word:
            guard let word = Self.filled(codeWord) else { return nil }
            return String(localized: "Are you \(word)? I'm the other one.")
        case .spot:
            guard let spot = Self.filled(meetingSpot) else { return nil }
            return String(localized: "Want to find a seat at \(spot)?")
        }
    }

    /// The value without surrounding spaces, or nil if there's nothing in it.
    private static func filled(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The chips to show, in order. Just chat has no glow, so it gets the room chip alone.
    static func chips(roomName: String?, codeWord: String?, meetingSpot: String?) -> [ChatIcebreakerChip] {
        allCases.compactMap { icebreaker in
            icebreaker.text(roomName: roomName, codeWord: codeWord, meetingSpot: meetingSpot)
                .map { ChatIcebreakerChip(icebreaker: icebreaker, text: $0) }
        }
    }

    /// The composer's text after a chip is tapped. An empty composer, or one still holding the last
    /// chip's text untouched, is replaced. Anything the person wrote or changed is kept, with the
    /// chip added after it. It never sends.
    static func filled(draft: String, replacing last: String?, with chip: ChatIcebreakerChip) -> String {
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty || draft == last ? chip.text : current + " " + chip.text
    }

    /// The chip's ID as an analytics value. Literals only, so no text can get in (AnalyticsValue).
    var analyticsValue: AnalyticsValue {
        switch self {
        case .room: "room"
        case .word: "word"
        case .spot: "spot"
        }
    }
}

/// A chip as shown: its opener and the text it fills in.
struct ChatIcebreakerChip: Identifiable, Hashable, Sendable {
    let icebreaker: ChatIcebreaker
    let text: String

    var id: String {
        icebreaker.id
    }
}

// MARK: - The chips on screen

/// The chips under the empty thread's message. Each is a button that fills the composer.
struct ChatIcebreakerChips: View {
    let chips: [ChatIcebreakerChip]
    let onUse: (ChatIcebreakerChip) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            Text("Need a way to start?")
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(chips) { chip in
                Button { onUse(chip) } label: {
                    Text(chip.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ChatIcebreakerStyle())
                .accessibilityLabel(Text("Suggested opener: \(chip.text)"))
                .accessibilityHint(Text("Puts it in the message box. Nothing is sent until you send it."))
            }
            Text("Tap one to start your message. You can change it first.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .padding(.top, GlowSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A wide chip that wraps its text at any size. B6's `GlowChip` caps text at two lines, which would
/// cut an opener off at the largest accessibility sizes. Same colors, type and corners, no motion.
struct ChatIcebreakerStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .subheadline) private var minHeight = GlowSize.chipHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glowFont(.chip)
            .foregroundStyle(.glowTextPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, GlowSpacing.md)
            .padding(.vertical, GlowSpacing.xs)
            .frame(minHeight: max(minHeight, GlowSize.minimumTapTarget))
            .background(
                (configuration.isPressed ? GlowPalette.surfaceRaised : GlowPalette.surface).color,
                in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous),
            )
            .overlay {
                RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
                    .strokeBorder(.glowLine, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
    }
}
