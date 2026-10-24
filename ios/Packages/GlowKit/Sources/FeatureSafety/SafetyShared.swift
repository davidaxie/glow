import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: B8. The block and report sheets and the pause and delete screens. The app shows them for
// `.block`, `.report`, `.pause` and `.deleteAccount`; keep these public initializers.
// Colors, type and buttons come from DesignSystem (B6) only.

// MARK: - Shared pieces

/// The finished state of a block or report: one calm line, then Close. From a match or chat,
/// Close goes back to the matches list, since that match has ended.
struct SafetyDone: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let context: SafetyContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate

    var body: some View {
        GlowSheetContent(title: title, message: message, systemImage: "checkmark.circle") {
            EmptyView()
        } actions: {
            Button("Close") {
                dismiss()
                if context.matchID != nil {
                    navigate(.matches)
                }
            }
            .buttonStyle(.glowPrimary)
        }
    }
}

/// A failure, in words, or nothing.
struct SafetyFailureText: View {
    let phase: SafetyPhase

    var body: some View {
        if case let .failed(failure) = phase {
            Label {
                Text(failure.message)
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextPrimary)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.glowDanger)
            }
        }
    }
}

extension SafetyFailure {
    var message: LocalizedStringKey {
        switch self {
        case .gone: "They're not here anymore. Their card or match has already ended."
        case .offline: "You're offline. Try again when you're connected."
        case .rateLimited: "That's a lot of tries. Wait a moment and try again."
        case .unexpected: "Something went wrong. Try again."
        }
    }
}

extension EnvironmentValues {
    /// Switches the block sheet to the report form.
    @Entry var safetyStartReport: @MainActor @Sendable () -> Void = {}
}
