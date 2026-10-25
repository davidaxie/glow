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

/// The lines, drawn in the glow's ink so they read like the rest of the screen: set as quotes in
/// New York italic, separated by hairlines, like lines in a script (U3).
struct GlowSayAloudView: View {
    let lines: [GlowSayAloudLine]
    @Environment(\.glowHue) private var hue

    var body: some View {
        if !lines.isEmpty {
            VStack(spacing: GlowSpacing.sm) {
                Text("Need an excuse?")
                    .glowFont(.footnote)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .kerning(1.2)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        if index > 0 {
                            Rectangle()
                                .fill((hue ?? .pearl).ink.color.opacity(0.18))
                                .frame(height: 1)
                                .padding(.horizontal, GlowSpacing.xl)
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: "\u{201C}\(line.text)\u{201D}")
                            .font(GlowMoment.serif(.title3))
                            .italic()
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, GlowSpacing.md)
                            .padding(.vertical, GlowSpacing.sm)
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Suggested opener: \(line.text)"))
                    }
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}
