import DesignSystem
import SwiftUI

// Owner: C4. Where people write their own messages: a field and a send button. No AI. Tapping an
// icebreaker chip (CHIPS-D1) only fills the field; the person still edits it and taps send.

struct ChatComposer: View {
    @Binding var draft: String
    let remaining: Int
    let canSend: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void

    /// The counter shows once the message gets close to the limit.
    static let counterThreshold = 100

    var body: some View {
        VStack(alignment: .trailing, spacing: GlowSpacing.xxs) {
            HStack(alignment: .bottom, spacing: GlowSpacing.xs) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 6)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextPrimary)
                    .tint(.glowAccent)
                    .focused(focus)
                    .padding(.horizontal, GlowSpacing.md)
                    .padding(.vertical, GlowSpacing.xs + 2)
                    .frame(minHeight: GlowSize.minimumTapTarget)
                    .background(.glowSurface, in: RoundedRectangle(cornerRadius: ChatStyle.bubbleRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ChatStyle.bubbleRadius, style: .continuous)
                            .strokeBorder(remaining < 0 ? .glowDanger : .glowLine, lineWidth: 1)
                    }
                    .accessibilityLabel(Text("Message"))

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.glow(.headline))
                        .fontWeight(.bold)
                        .foregroundStyle(canSend ? .glowOnAccent : .glowTextSecondary)
                        .frame(width: GlowSize.minimumTapTarget - 6, height: GlowSize.minimumTapTarget - 6)
                        .background(canSend ? .glowAccent : .glowSurfaceRaised, in: Circle())
                        .frame(minWidth: GlowSize.minimumTapTarget, minHeight: GlowSize.minimumTapTarget)
                        .contentShape(Rectangle())
                        .animation(ChatStyle.snappy, value: canSend)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(Text("Send"))
            }

            if remaining < Self.counterThreshold {
                Text(counterText)
                    .glowFont(.caption)
                    .foregroundStyle(remaining < 0 ? .glowDanger : .glowTextSecondary)
                    .padding(.trailing, GlowSize.minimumTapTarget + GlowSpacing.xs)
                    .accessibilityLabel(Text(counterText))
            }
        }
        .padding(.horizontal, GlowSpacing.md)
        .padding(.vertical, GlowSpacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(GlowPalette.line.color.opacity(0.6)).frame(height: 1)
        }
    }

    private var counterText: String {
        if remaining < 0 {
            return String(localized: "\(-remaining) over the limit")
        }
        return String(localized: "\(remaining) left")
    }
}
