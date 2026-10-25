import AppCore
import DesignSystem
import SwiftUI

// Owner: C4. One message: mine on the right in the accent color, theirs on the left. Text is
// shown exactly as written (never as Markdown or links), with no suggested replies in the thread.

struct ChatBubble: View {
    let row: ChatRow
    /// "Sam", or "They" before the header has loaded. Only used in VoiceOver labels.
    let otherName: String
    let calendar: Calendar
    var onRetry: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var choosingFix = false

    nonisolated static let sendingOpacity = 0.85

    private var message: ChatMessage {
        row.message
    }

    var body: some View {
        VStack(alignment: message.fromMe ? .trailing : .leading, spacing: GlowSpacing.xxs) {
            HStack(spacing: 0) {
                if message.fromMe {
                    Spacer(minLength: GlowSpacing.xxl)
                }
                bubble
                if !message.fromMe {
                    Spacer(minLength: GlowSpacing.xxl)
                }
            }
            status
        }
        .frame(maxWidth: .infinity, alignment: message.fromMe ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isFailed ? Text("Double-tap for options.") : Text(verbatim: ""))
        .accessibilityAction {
            if isFailed {
                choosingFix = true
            }
        }
        .accessibilityActions {
            if canRetry {
                Button("Try again", action: onRetry)
            }
            if isFailed {
                Button("Edit", action: onEdit)
                Button("Delete", action: onDelete)
            }
        }
        .confirmationDialog(Text(failureTitle), isPresented: $choosingFix, titleVisibility: .visible) {
            if canRetry {
                Button("Try again", action: onRetry)
            }
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Large continuous corners, tighter on the sender's side where a run of messages joins (U3).
    private var shape: UnevenRoundedRectangle {
        let full = ChatStyle.bubbleRadius
        let joined = row.continuesGroup ? ChatStyle.joinedRadius : full
        return UnevenRoundedRectangle(
            topLeadingRadius: message.fromMe ? full : joined,
            bottomLeadingRadius: full,
            bottomTrailingRadius: full,
            topTrailingRadius: message.fromMe ? joined : full,
            style: .continuous,
        )
    }

    /// Mine: the accent, lit a touch from above. Theirs: a lifted surface. Lightening the accent
    /// only raises the dark ink's contrast.
    private var fill: AnyShapeStyle {
        if message.fromMe {
            return AnyShapeStyle(LinearGradient(
                colors: [GlowPalette.accent.mixed(with: .white, amount: 0.12).color, GlowPalette.accent.color],
                startPoint: .top,
                endPoint: .bottom,
            ))
        }
        return AnyShapeStyle(GlowPalette.surfaceRaised.color)
    }

    private var bubble: some View {
        Text(verbatim: message.body)
            .glowFont(.body)
            .foregroundStyle(message.fromMe ? .glowOnAccent : .glowTextPrimary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(.horizontal, GlowSpacing.md)
            .padding(.vertical, GlowSpacing.sm - 2)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            GlowPalette.textPrimary.color.opacity(message.fromMe ? 0.25 : 0.1),
                            GlowPalette.textPrimary.color.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .center,
                    ),
                    lineWidth: 1,
                )
            }
            // A little quieter while it's on its way. 85% keeps the text at 4.9:1 on the faded
            // accent (WCAG AA); 60% would drop it to 2.9:1.
            .opacity(message.delivery == .sending ? Self.sendingOpacity : 1)
            .contentShape(shape)
            .onTapGesture {
                if isFailed {
                    choosingFix = true
                }
            }
    }

    @ViewBuilder private var status: some View {
        switch message.delivery {
        case .sending:
            Text("Sending…")
                .glowFont(.caption)
                .foregroundStyle(.glowTextSecondary)
        case let .failed(reason):
            Button {
                choosingFix = true
            } label: {
                Label {
                    Text(failureLine(reason))
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .glowFont(.caption)
                .foregroundStyle(.glowDanger)
            }
            .buttonStyle(.plain)
        case .sent:
            if row.showsSent {
                Text("Sent")
                    .glowFont(.caption)
                    .foregroundStyle(.glowTextSecondary)
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = message.delivery {
            return true
        }
        return false
    }

    private var canRetry: Bool {
        if case let .failed(reason) = message.delivery {
            return reason != .rejected
        }
        return false
    }

    private var failureTitle: String {
        if case .failed(.rejected) = message.delivery {
            return String(localized: "This message can't be sent. You can edit it or delete it.")
        }
        return String(localized: "This message didn't send.")
    }

    private func failureLine(_ reason: SendFailure) -> String {
        switch reason {
        case .rejected: String(localized: "Not sent. Try saying it another way.")
        case .rateLimited: String(localized: "Not sent. Wait a moment, then tap to try again.")
        case .network: String(localized: "Not sent. Tap to try again.")
        }
    }

    private var accessibilityLabel: Text {
        let speaker = message.fromMe ? String(localized: "You") : otherName
        let time = ChatLayout.time(message.createdAt, calendar: calendar)
        let state: String = switch message.delivery {
        case .sent: time
        case .sending: String(localized: "Sending")
        case .failed: String(localized: "Not sent")
        }
        return Text(verbatim: "\(speaker), \(state): \(message.body)")
    }
}
