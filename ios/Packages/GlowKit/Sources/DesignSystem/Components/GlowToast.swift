import SwiftUI

// Owner: B6. Toasts: a short, calm note that comes and goes on its own.
//
//     @State private var toast: GlowToastMessage?
//     …
//     .glowToast($toast)
//     …
//     toast = GlowToastMessage(String(localized: "Done. They won't see you again."), kind: .success)

/// One toast.
public struct GlowToastMessage: Identifiable, Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case info, success, error

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }

        var iconColor: GlowRGB {
            switch self {
            case .info: GlowPalette.textSecondary
            case .success: GlowPalette.accent
            case .error: GlowPalette.danger
            }
        }
    }

    public let id: UUID
    public let text: String
    public let kind: Kind
    /// How long it stays when VoiceOver is off.
    public let duration: Duration

    /// - Parameter text: already localized, like `String(localized: "Saved")`.
    public init(_ text: String, kind: Kind = .info, duration: Duration = .seconds(3)) {
        id = UUID()
        self.text = text
        self.kind = kind
        self.duration = duration
    }

    /// How long it actually stays. VoiceOver users get longer, so the announcement can finish and
    /// they can still find the toast.
    public func displayDuration(voiceOverEnabled: Bool) -> Duration {
        voiceOverEnabled ? max(duration * 2, .seconds(6)) : duration
    }
}

/// The toast's look, on its own.
public struct GlowToast: View {
    private let message: GlowToastMessage

    public init(_ message: GlowToastMessage) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.sm) {
            Image(systemName: message.kind.systemImage)
                .foregroundStyle(message.kind.iconColor.color)
                .accessibilityHidden(true)
            Text(message.text)
                .foregroundStyle(.glowTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glowFont(.callout)
        .padding(.horizontal, GlowSpacing.md)
        .padding(.vertical, GlowSpacing.sm)
        .background(.glowSurfaceRaised, in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
                .strokeBorder(.glowLine, lineWidth: 1)
        }
        .shadow(color: .glowBackground.opacity(0.6), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `message` as a toast at the top (or bottom) of this view, then clears it after its
    /// duration. Tap or swipe it away sooner. VoiceOver reads it out as it appears.
    public func glowToast(_ message: Binding<GlowToastMessage?>, edge: VerticalEdge = .top) -> some View {
        modifier(GlowToastPresenter(message: message, edge: edge))
    }
}

private struct GlowToastPresenter: ViewModifier {
    @Binding var message: GlowToastMessage?
    let edge: VerticalEdge

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                ZStack {
                    if let message {
                        GlowToast(message)
                            .padding(.horizontal, GlowSpacing.md)
                            .padding(edge == .top ? .top : .bottom, GlowSpacing.xs)
                            .transition(GlowMotion.transition(from: edge == .top ? .top : .bottom, reduceMotion: reduceMotion))
                            .onTapGesture { dismiss(message) }
                            .accessibilityAction(named: Text("Dismiss")) { dismiss(message) }
                            .id(message.id)
                    }
                }
                .animation(GlowMotion.ui, value: message)
            }
            .task(id: message?.id) {
                guard let shown = message else { return }
                AccessibilityNotification.Announcement(shown.text).post()
                try? await Task.sleep(for: shown.displayDuration(voiceOverEnabled: voiceOverEnabled))
                if !Task.isCancelled {
                    dismiss(shown)
                }
            }
    }

    private func dismiss(_ shown: GlowToastMessage) {
        if message?.id == shown.id {
            message = nil
        }
    }
}
