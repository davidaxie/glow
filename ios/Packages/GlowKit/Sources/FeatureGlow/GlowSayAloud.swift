import DesignSystem
import SwiftUI

// Owner: C3 (CHIPS-D1, added with David's approval). "Need an excuse?": three lines to say out loud,
// under the code word and the meeting spot on the glow screen, which exists only after a mutual
// match and both choosing Find.
//
// They are for reading, not tapping: nothing here is a button, and nothing is sent or filled in
// anywhere. They are static text. The only things filled in are the code word and the meeting spot
// the screen already shows. A line whose piece is missing is left out rather than shown with a hole.

/// One line to say aloud. The ID is stable; nothing about a line goes to analytics.
struct GlowSayAloudLine: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
}

enum GlowSayAloud {
    /// The lines for this glow, in order. Without a meeting spot there are two.
    static func lines(codeWord: String, meetingSpot: String?) -> [GlowSayAloudLine] {
        var lines: [GlowSayAloudLine] = []
        if let word = filled(codeWord) {
            lines.append(GlowSayAloudLine(id: "word", text: String(localized: "Are you \(word)?")))
        }
        lines.append(GlowSayAloudLine(id: "noticed", text: String(localized: "We both noticed. Hi.")))
        if let spot = filled(meetingSpot) {
            lines.append(GlowSayAloudLine(id: "spot", text: String(localized: "Found you. Shall we sit by \(spot)?")))
        }
        return lines
    }

    /// The value without surrounding spaces, or nil if there's nothing in it.
    private static func filled(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The lines, drawn in the glow's ink so they read like the rest of the screen.
struct GlowSayAloudView: View {
    let lines: [GlowSayAloudLine]
    @Environment(\.glowHue) private var hue

    var body: some View {
        if !lines.isEmpty {
            VStack(spacing: GlowSpacing.xs) {
                Text("Need an excuse?")
                    .glowFont(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(lines) { line in
                    Text(line.text)
                        .glowFont(.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GlowSpacing.md)
                        .padding(.vertical, GlowSpacing.xs)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
                                .strokeBorder((hue ?? .pearl).ink.color.opacity(0.5), lineWidth: 1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Suggested opener: \(line.text)"))
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}
