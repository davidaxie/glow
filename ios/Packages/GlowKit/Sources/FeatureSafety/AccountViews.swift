import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: B8. The block and report sheets and the pause and delete screens. The app shows them for
// `.block`, `.report`, `.pause` and `.deleteAccount`; keep these public initializers.
// Colors, type and buttons come from DesignSystem (B6) only.

// MARK: - Pause

/// Pause or resume being visible. While paused, your card leaves every deck at once (P8).
public struct PauseView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model: PauseModel?

    public init() {}

    public var body: some View {
        Group {
            if let model {
                PauseContent(model: model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.glowBackground)
        .navigationTitle("Pause")
        .task {
            if model == nil {
                let model = PauseModel(
                    api: dependencies.api,
                    session: dependencies.session,
                    analytics: dependencies.analytics,
                )
                await model.load()
                self.model = model
            }
        }
    }
}

struct PauseContent: View {
    let model: PauseModel

    private var paused: Bool {
        model.paused
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                Toggle(isOn: Binding(
                    get: { paused },
                    set: { newValue in Task { await model.setPaused(newValue) } },
                )) {
                    VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                        Text("Pause my card")
                            .glowFont(.headline)
                            .foregroundStyle(.glowTextPrimary)
                        Text(paused ? "Paused. Nobody can see or tap you." : "Visible in rooms you're checked into.")
                            .glowFont(.callout)
                            .foregroundStyle(.glowTextSecondary)
                    }
                }
                .tint(.glowAccent)
                .disabled(!model.isLoaded || model.phase.isWorking)
                .padding(GlowSpacing.md)
                .background(.glowSurface, in: .rect(cornerRadius: GlowRadius.card))
                .accessibilityHint(paused ? "Turn off to be seen in rooms again." : "Hides you from every deck at once.")

                Text(
                    """
                    While you're paused, your card leaves every deck at once and nobody can tap you. \
                    Your matches and chats stay as they are. Resume whenever you like.
                    """,
                )
                .glowFont(.body)
                .foregroundStyle(.glowTextSecondary)

                SafetyFailureText(phase: model.phase)
            }
            .padding(GlowSpacing.screenMargin)
        }
    }
}

// MARK: - Delete account

/// Deletes the account and everything in it, then signs out.
public struct DeleteAccountView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var model: DeleteAccountModel?

    public init() {}

    public var body: some View {
        Group {
            if let model {
                DeleteAccountContent(model: model)
            } else {
                Color.glowClear
            }
        }
        .background(.glowBackground)
        .navigationTitle("Delete account")
        .task {
            if model == nil {
                model = DeleteAccountModel(
                    api: dependencies.api,
                    session: dependencies.session,
                    analytics: dependencies.analytics,
                )
            }
        }
    }
}

struct DeleteAccountContent: View {
    let model: DeleteAccountModel
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                Text("This deletes everything")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: GlowSpacing.sm) {
                    DeletedItem(text: "Your profile and photos", systemImage: "person.crop.square")
                    DeletedItem(text: "Your cards in every room", systemImage: "rectangle.portrait")
                    DeletedItem(text: "Your matches and chats", systemImage: "bubble.left.and.bubble.right")
                    DeletedItem(text: "Your sign-in", systemImage: "key")
                }
                .padding(GlowSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.glowSurface, in: .rect(cornerRadius: GlowRadius.card))

                Text("People you matched with will see the match end. This can't be undone.")
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)

                SafetyFailureText(phase: model.phase)

                Button("Delete my account") { confirming = true }
                    .buttonStyle(.glowDanger)
                    .glowLoading(model.phase.isWorking)
                    .disabled(model.phase == .done)
            }
            .padding(GlowSpacing.screenMargin)
        }
        .confirmationDialog(
            "Delete your account for good?",
            isPresented: $confirming,
            titleVisibility: .visible,
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await model.delete() }
            }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct DeletedItem: View {
    let text: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(text)
                .glowFont(.body)
                .foregroundStyle(.glowTextPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.glowDanger)
        }
    }
}

#Preview("Pause") {
    NavigationStack { PauseView() }
}

#Preview("Delete") {
    NavigationStack { DeleteAccountView() }
}
