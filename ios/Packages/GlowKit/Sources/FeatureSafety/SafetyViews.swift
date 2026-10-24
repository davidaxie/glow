import APIClient
import AppCore
import SwiftUI

// Owner: B8. The block and report sheets and the pause and delete screens. The app shows them for
// `.block`, `.report`, `.pause` and `.deleteAccount`; keep these public initializers.

// MARK: - Block

/// Shown as a sheet from a card, a match or a chat. Blocking applies both ways, everywhere, at once
/// (P7), ends any match and chat between the two, and the other person isn't told.
public struct BlockSheet: View {
    public let context: SafetyContext
    @Environment(\.dependencies) private var dependencies
    @State private var model: BlockModel?
    @State private var reporting = false

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        NavigationStack {
            Group {
                if reporting {
                    ReportForm(context: context)
                } else if let model {
                    BlockContent(model: model)
                }
            }
            .toolbar { SafetyCloseButton() }
        }
        .task {
            if model == nil {
                model = BlockModel(context: context, api: dependencies.api, analytics: dependencies.analytics)
            }
        }
        .environment(\.safetyStartReport) { reporting = true }
    }
}

struct BlockContent: View {
    let model: BlockModel

    var body: some View {
        if model.phase == .done {
            SafetyDone(
                title: "Done. They won't see you again.",
                message: model.context.matchID == nil
                    ? "Their card is gone from your deck, and yours from theirs."
                    : "Your match and chat with them have ended.",
                context: model.context,
            )
        } else {
            BlockConfirm(model: model)
        }
    }
}

private struct BlockConfirm: View {
    let model: BlockModel
    @Environment(\.safetyStartReport) private var startReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "hand.raised")
                    .imageScale(.large)
                    .accessibilityHidden(true)
                Text("Block this person?")
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                Text("You won't see each other anywhere in Glow, and they aren't told.")
                if model.context.matchID != nil {
                    Text("Your match and chat with them end too.")
                }
                SafetyFailureText(phase: model.phase)
                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        Task { await model.block() }
                    } label: {
                        SafetyButtonLabel(title: "Block", working: model.phase.isWorking)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase.isWorking)
                    .accessibilityHint("They won't see you again, and they aren't told.")

                    Button("Report instead") { startReport() }
                        .disabled(model.phase.isWorking)
                        .accessibilityHint("Reporting also blocks them.")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle("Block")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Report

/// Shown as a sheet from a card, a match or a chat. Reporting also blocks.
public struct ReportSheet: View {
    public let context: SafetyContext

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        NavigationStack {
            ReportForm(context: context)
                .toolbar { SafetyCloseButton() }
        }
    }
}

struct ReportForm: View {
    let context: SafetyContext
    @Environment(\.dependencies) private var dependencies
    @State private var model: ReportModel?

    var body: some View {
        Group {
            if let model {
                ReportContent(model: model)
            }
        }
        .task {
            if model == nil {
                model = ReportModel(context: context, api: dependencies.api, analytics: dependencies.analytics)
            }
        }
    }
}

struct ReportContent: View {
    @Bindable var model: ReportModel

    var body: some View {
        if model.phase == .done {
            SafetyDone(
                title: "Thanks for telling us.",
                message: "We'll look into it. They won't see you again, and they aren't told who reported.",
                context: model.context,
            )
        } else {
            Form {
                Section {
                    ForEach(ReportReason.allCases) { reason in
                        ReasonRow(reason: reason, selected: model.reason == reason) {
                            model.reason = reason
                        }
                    }
                } header: {
                    Text("What happened?")
                } footer: {
                    Text("Reporting also blocks them. They aren't told who reported.")
                }

                Section {
                    TextField("Anything else we should know?", text: $model.details, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .accessibilityLabel("Details, optional")
                } header: {
                    Text("Details (optional)")
                } footer: {
                    Text("\(model.details.count) of \(ReportModel.maxDetails) characters")
                        .accessibilityLabel("\(model.details.count) of \(ReportModel.maxDetails) characters used")
                }

                Section {
                    SafetyFailureText(phase: model.phase)
                    Button(role: .destructive) {
                        Task { await model.submit() }
                    } label: {
                        SafetyButtonLabel(title: "Report and block", working: model.phase.isWorking)
                    }
                    .disabled(!model.canSubmit)
                    .accessibilityHint(model.reason == nil ? "Choose what happened first." : "")
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ReasonRow: View {
    let reason: ReportReason
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(reason.title)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

extension ReportReason {
    var title: LocalizedStringKey {
        switch self {
        case .harassment: "Harassment or bullying"
        case .inappropriatePhoto: "Inappropriate photo"
        case .underage: "Might be under 18"
        case .spam: "Spam or a scam"
        case .unsafe: "Made me feel unsafe"
        case .other: "Something else"
        }
    }
}

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
            }
        }
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

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { model.paused ?? false },
                    set: { newValue in Task { await model.setPaused(newValue) } },
                )) {
                    Text("Pause my card")
                }
                .disabled(model.paused == nil || model.phase.isWorking)
                .accessibilityHint(model.paused == true ? "Turn off to be seen in rooms again." : "Hides you from every deck.")
            } footer: {
                Text(model.paused == true
                    ? "You're paused. Nobody sees your card in any room, and nobody can tap you."
                    : "While you're paused, your card leaves every deck at once and nobody can tap you.")
            }

            Section {
                Text("Your matches and chats stay as they are. Resume whenever you like.")
                SafetyFailureText(phase: model.phase)
            }
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
            }
        }
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
        Form {
            Section {
                Label("Your profile and photos", systemImage: "person.crop.square")
                Label("Your cards in every room", systemImage: "rectangle.portrait")
                Label("Your matches and chats", systemImage: "bubble.left.and.bubble.right")
                Label("Your sign-in", systemImage: "key")
            } header: {
                Text("This deletes everything")
            } footer: {
                Text("People you matched with will see the match end. This can't be undone.")
            }

            Section {
                SafetyFailureText(phase: model.phase)
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    SafetyButtonLabel(title: "Delete my account", working: model.phase.isWorking)
                }
                .disabled(model.phase.isWorking || model.phase == .done)
            }
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
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .imageScale(.large)
                .accessibilityHidden(true)
            Text(title)
                .bold()
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .multilineTextAlignment(.center)
            Button("Close") {
                dismiss()
                if context.matchID != nil { navigate(.matches) }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A failure, in words, or nothing.
struct SafetyFailureText: View {
    let phase: SafetyPhase

    var body: some View {
        if case let .failed(failure) = phase {
            Label(failure.message, systemImage: "exclamationmark.circle")
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

/// A button title that turns into a spinner while working, and says so to VoiceOver.
struct SafetyButtonLabel: View {
    let title: LocalizedStringKey
    let working: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(working ? 0 : 1)
            if working {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(working ? Text("In progress") : Text(""))
    }
}

struct SafetyCloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }
}

private struct StartReportKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    /// Switches the block sheet to the report form.
    var safetyStartReport: @MainActor @Sendable () -> Void {
        get { self[StartReportKey.self] }
        set { self[StartReportKey.self] = newValue }
    }
}

#Preview("Block") {
    BlockSheet(context: .card(CardID(rawValue: "00000000-0000-4000-8000-000000000003")))
}

#Preview("Report") {
    ReportSheet(context: .chat(MatchID(rawValue: "00000000-0000-4000-8000-000000000001")))
}

#Preview("Pause") {
    NavigationStack { PauseView() }
}

#Preview("Delete") {
    NavigationStack { DeleteAccountView() }
}
