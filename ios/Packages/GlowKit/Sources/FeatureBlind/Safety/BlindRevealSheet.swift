import AppCore
import DesignSystem
import Observation
import SwiftUI

/// The Reveal flow for one chat, ported from Double Blind's RevealModel.
@MainActor
@Observable
final class BlindRevealModel {
    private(set) var phase: BlindRevealPhase

    init(phase: BlindRevealPhase = .ready) {
        self.phase = phase
    }

    /// Taps Reveal. A repeated tap while waiting does nothing; the server is idempotent anyway.
    func tap(_ chatID: BlindChatID, using service: any BlindService) async {
        switch phase {
        case .ready, .failed: break
        default: return
        }
        phase = .sending
        do throws(BlindError) {
            phase = try await BlindRevealPhase.phase(after: service.reveal(chatID))
        } catch .notFound {
            // The chat is gone for me (they left, or it was closed): the same as "they left".
            phase = .left
        } catch {
            phase = .failed(error.message)
        }
    }

    /// Adopts what the server says when the sheet opens. Only moves off `ready`.
    func sync(_ chatID: BlindChatID, using service: any BlindService) async {
        guard phase == .ready else { return }
        do throws(BlindError) {
            let next = try await BlindRevealPhase.phase(for: service.chat(chatID))
            if phase == .ready {
                phase = next
            }
        } catch .notFound {
            if phase == .ready {
                phase = .left
            }
        } catch {
            // Offline: stay on ready; tapping is idempotent on the server.
        }
    }

    /// Re-reads the chat while waiting, to notice their tap, their leaving, or a block.
    func refresh(_ chatID: BlindChatID, using service: any BlindService) async {
        guard phase == .waiting else { return }
        do throws(BlindError) {
            let next = try await BlindRevealPhase.phase(for: service.chat(chatID))
            if next != .ready {
                phase = next
            }
        } catch .notFound {
            phase = .left
        } catch {
            // A failed poll changes nothing; the next one tries again.
        }
    }
}

/// The reveal sheet. B5: a one-sided tap shows the tapper only "Waiting for them", breathing.
/// Nothing tells the other person anything. When both have tapped, the reveal screen opens.
struct BlindRevealSheet: View {
    let chatID: BlindChatID
    let service: any BlindService
    let onChange: () -> Void
    let onRevealed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: BlindRevealModel

    init(
        chatID: BlindChatID,
        service: any BlindService,
        iTappedReveal: Bool,
        onChange: @escaping () -> Void,
        onRevealed: @escaping () -> Void,
    ) {
        self.chatID = chatID
        self.service = service
        self.onChange = onChange
        self.onRevealed = onRevealed
        _model = State(initialValue: BlindRevealModel(phase: iTappedReveal ? .waiting : .ready))
    }

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            icon
            VStack(spacing: GlowSpacing.xs) {
                Text(title)
                    .font(BlindType.statement)
                    .foregroundStyle(.glowTextPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("blind.reveal.title")
                Text(message)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blind.reveal.sheet")
        .task { await model.sync(chatID, using: service) }
        .task(id: model.phase) { await poll() }
        .glowHaptic(.success, trigger: model.phase == .waiting)
        .onChange(of: model.phase) { _, phase in
            onChange()
            if phase == .revealed {
                onRevealed()
            }
        }
    }

    private var icon: some View {
        ZStack {
            BlindVeilOrb(seed: chatID.rawValue, size: 76, drifts: model.phase != .left)
            Image(systemName: symbol)
                .glowFont(.title)
                .foregroundStyle(.glowTextPrimary)
        }
        .blindBreathing(model.phase == .waiting)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch model.phase {
        case .waiting: "hourglass"
        case .left: "person.fill.xmark"
        case .revealed: "checkmark"
        default: "eye"
        }
    }

    private var title: String {
        switch model.phase {
        case .ready, .sending, .failed: String(localized: "Ready to reveal?")
        case .waiting: String(localized: "Waiting for them")
        case .revealed: String(localized: "You both said yes")
        case .left: String(localized: "They've left this chat")
        }
    }

    private var message: String {
        switch model.phase {
        case .ready, .sending:
            String(localized: "If you both tap Reveal, you'll see each other's name and photos. If only you tap, they won't know.")
        case .waiting:
            String(localized: "You've tapped. If they tap too, you'll both see each other. Until then, nothing changes for them.")
        case .revealed:
            String(localized: "Lifting the veil.")
        case .left:
            String(localized: "Reveal isn't possible any more.")
        case let .failed(text):
            text
        }
    }

    private var actions: some View {
        VStack(spacing: GlowSpacing.xs) {
            switch model.phase {
            case .ready, .sending, .failed:
                Button("Reveal") { Task { await model.tap(chatID, using: service) } }
                    .buttonStyle(.glowPrimary)
                    .glowLoading(model.phase == .sending)
                    .accessibilityIdentifier("blind.reveal.confirm")
                Button("Not yet") { dismiss() }
                    .buttonStyle(.glowQuiet)
                    .accessibilityIdentifier("blind.reveal.cancel")
            case .waiting, .left:
                Button("Close") { dismiss() }
                    .buttonStyle(.glowSecondary)
                    .accessibilityIdentifier("blind.reveal.close")
            case .revealed:
                Button("Continue") {}.buttonStyle(.glowPrimary).glowLoading(true)
            }
        }
    }

    /// While waiting, look at the chat every 1.5 s to notice their tap.
    private func poll() async {
        guard model.phase == .waiting else { return }
        while !Task.isCancelled, model.phase == .waiting {
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled {
                return
            }
            await model.refresh(chatID, using: service)
        }
    }
}

/// The chat's "…" menu: Guess who, Report, Leave chat, Block. Leave and Block ask first.
///
/// Leaving tells them only that I left. Blocking closes the chat for both, hides each of us from the
/// other everywhere in Glow (Rooms too), and never tells me who they were.
struct BlindChatMenu: View {
    let chatID: BlindChatID
    let status: BlindChatStatus
    let service: any BlindService

    private enum Pending: Identifiable {
        case leave, block

        var id: Self {
            self
        }
    }

    @Environment(\.navigate) private var navigate
    @State private var pending: Pending?
    @State private var errorText: String?
    @State private var done = 0

    var body: some View {
        let items = BlindMenuItems(status: status)
        Menu {
            if items.guess {
                Button("Guess who", systemImage: "questionmark.circle") { navigate(.blindGuess(chatID)) }
            }
            if items.report {
                Button("Report", systemImage: "flag") { navigate(.blindReport(chatID)) }
            }
            if items.leave {
                Button("Leave chat", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { pending = .leave }
            }
            if items.block {
                Button("Block", systemImage: "nosign", role: .destructive) { pending = .block }
            }
        } label: {
            Image(systemName: "ellipsis")
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
                .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Chat options"))
        .accessibilityIdentifier("blind.chat.menu")
        .glowHaptic(.warning, trigger: done)
        .confirmationDialog(
            pending == .block ? "Block this person?" : "Leave this chat?",
            isPresented: Binding(get: { pending != nil }, set: {
                if !$0 {
                    pending = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pending,
        ) { pending in
            switch pending {
            case .leave:
                Button("Leave chat", role: .destructive) { Task { await run { () async throws(BlindError) in
                    try await service.leaveChat(chatID)
                } } }
            case .block:
                Button("Block", role: .destructive) { Task { await run { () async throws(BlindError) in
                    try await service.block(chatID)
                } } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            switch pending {
            case .leave:
                Text("They'll only see that you left. You can't come back to this chat.")
            case .block:
                Text(
                    "This closes the chat. You won't see each other again anywhere in Glow. They only see that you left, and you won't find out who they were.",
                )
            }
        }
        .alert("Couldn't do that", isPresented: Binding(get: { errorText != nil }, set: {
            if !$0 {
                errorText = nil
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func run(_ work: () async throws(BlindError) -> Void) async {
        do throws(BlindError) {
            try await work()
            done += 1
            navigate(.blind)
        } catch .notFound {
            // Already gone for me: the same outcome.
            navigate(.blind)
        } catch {
            errorText = error.message
        }
    }
}
