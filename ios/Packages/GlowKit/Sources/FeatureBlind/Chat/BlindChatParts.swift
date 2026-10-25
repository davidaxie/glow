import AppCore
import DesignSystem
import SwiftUI

// Owner: X2. Pieces of the blind chat: a bubble and the give-away warning sheet.

// MARK: - Bubble

struct BlindBubble: View {
    let row: BlindChatRow
    let groupedWithPrevious: Bool
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: row.mine ? .trailing : .leading, spacing: GlowSpacing.xxs) {
            Text(row.text)
                .glowFont(.body)
                .foregroundStyle(row.mine ? Color.glowOnAccent : Color.glowTextPrimary)
                .padding(.horizontal, GlowSpacing.md)
                .padding(.vertical, GlowSpacing.xs + 2)
                .background(
                    row.mine ? Color.glowAccent : Color.glowSurfaceRaised,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                )
                .overlay {
                    if row.state == .failed {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.glowDanger, lineWidth: 1.5)
                    }
                }
                .opacity(row.state == .sending ? 0.6 : 1)
                .frame(maxWidth: 300, alignment: row.mine ? .trailing : .leading)
            if row.state == .failed {
                HStack(spacing: GlowSpacing.sm) {
                    Text("Not sent.").foregroundStyle(.glowDanger)
                    Button("Retry", action: onRetry).foregroundStyle(.glowAccent)
                    Button("Delete", action: onDiscard).foregroundStyle(.glowTextSecondary)
                }
                .glowFont(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: row.mine ? .trailing : .leading)
        .padding(.top, groupedWithPrevious ? 0 : GlowSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.mine ? Text("You: \(row.text)") : Text("Them: \(row.text)"))
        .accessibilityIdentifier(row.mine ? "blind.bubble.mine" : "blind.bubble.theirs")
    }
}

// MARK: - Give-away warning

/// "This might give you away." Shown when the server held a message back. Nothing was sent yet.
/// Edit puts the text back in the composer; Send anyway repeats the request with `confirm`.
struct BlindGiveAwaySheet: View {
    let warning: BlindPendingWarning
    let onEdit: () -> Void
    let onSendAnyway: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.md) {
            HStack(spacing: GlowSpacing.sm) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .glowFont(.title)
                    .foregroundStyle(.glowAccent)
                    .accessibilityHidden(true)
                Text("This might give you away.")
                    .font(BlindType.statement)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(warning.reason)
                .glowFont(.body)
                .foregroundStyle(.glowTextSecondary)
            Text(warning.text)
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
                .lineLimit(3)
                .padding(GlowSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.glowSurfaceRaised, in: RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous))
            Text("Send anyway?")
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
            HStack(spacing: GlowSpacing.sm) {
                Button("Edit") {
                    onEdit()
                    dismiss()
                }
                .buttonStyle(.glowSecondary)
                .accessibilityIdentifier("blind.warning.edit")
                Button("Send anyway") {
                    onSendAnyway()
                    dismiss()
                }
                .buttonStyle(.glowPrimary)
                .accessibilityIdentifier("blind.warning.send")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blind.warning.sheet")
    }
}
