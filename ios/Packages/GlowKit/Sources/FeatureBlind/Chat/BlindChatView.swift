import AppCore
import DesignSystem
import SwiftUI

/// One blind chat under its codename: bubbles, composer, polling, optimistic send, the give-away
/// warning and the reveal sheet. Opened by `.blindChat(id)`.
public struct BlindChatView: View {
    let chatID: BlindChatID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: BlindChatModel?

    public init(chatID: BlindChatID) {
        self.chatID = chatID
    }

    public var body: some View {
        ZStack {
            BlindCanvas()
            if let model {
                BlindChatContent(model: model, service: dependencies.blindService(override: override))
            } else {
                BlindVeilOrb(seed: "chat", size: 72).blindBreathing()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Runs when the screen appears and whenever the app comes back, so it polls only in the
        // foreground (SwiftUI cancels the task when the phase changes or the view goes away).
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let model = model ?? makeModel()
            if model.loaded {
                await model.pollOnce()
                await model.refreshDetail()
            } else {
                await model.load()
            }
            await model.run()
        }
    }

    private func makeModel() -> BlindChatModel {
        let created = BlindChatModel(
            chatID: chatID,
            service: dependencies.blindService(override: override),
            analytics: dependencies.analytics,
        )
        let navigate = navigate
        let chatID = chatID
        created.onRevealed = { navigate(.blindReveal(chatID)) }
        created.onGone = { navigate(.blind) }
        model = created
        return created
    }
}

private struct BlindChatContent: View {
    let model: BlindChatModel
    let service: any BlindService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReveal = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            if model.theyLeft {
                leftBanner
            } else {
                composer
            }
        }
        .glowHaptic(.lightTap, trigger: model.arrivals)
        .glowSheet(item: Binding(get: { model.warning }, set: {
            if $0 == nil {
                model.editWarning()
            }
        })) { held in
            BlindGiveAwaySheet(warning: held, onEdit: { model.editWarning() }, onSendAnyway: { model.confirmWarning() })
        }
        .glowSheet(isPresented: $showReveal) {
            BlindRevealSheet(chatID: model.chatID, service: service, iTappedReveal: model.detail?.iTappedReveal == true) {
                Task { await model.refreshDetail() }
            } onRevealed: {
                showReveal = false
                navigate(.blindReveal(model.chatID))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: GlowSpacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                    .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back to chats"))
            .accessibilityIdentifier("blind.chat.back")

            BlindVeilOrb(seed: model.codename, size: 40, drifts: !model.isRevealed)

            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(BlindType.codename)
                    .foregroundStyle(.glowTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("blind.chat.title")
                Text(statusLine)
                    .glowFont(.caption)
                    .foregroundStyle(model.connection == .offline ? .glowDanger : .glowTextSecondary)
            }
            Spacer(minLength: GlowSpacing.xs)
            if !model.theyLeft {
                revealPill
            }
            BlindChatMenu(chatID: model.chatID, status: model.detail?.status ?? .open, service: service)
        }
        .padding(.horizontal, GlowSpacing.xs)
        .padding(.vertical, GlowSpacing.xxs)
        .overlay(alignment: .bottom) { Rectangle().fill(.glowLine).frame(height: 1) }
    }

    private var statusLine: String {
        if model.connection == .offline {
            return String(localized: "Reconnecting…")
        }
        if model.theyLeft {
            return String(localized: "They left")
        }
        if model.isRevealed {
            return String(localized: "You knew them as \(model.codename)")
        }
        return String(localized: "Blind chat")
    }

    /// B5: before the reveal the pill depends only on MY tap. Nothing here can show whether they tapped.
    private var revealPill: some View {
        let pill = BlindChatRules.revealPill(model.detail)
        return Button {
            if pill == .revealed {
                navigate(.blindReveal(model.chatID))
            } else {
                showReveal = true
            }
        } label: {
            Text(pill == .revealed ? "Revealed" : pill == .waiting ? "Waiting" : "Reveal")
                .glowFont(.chip)
                .foregroundStyle(pill == .waiting ? Color.glowTextSecondary : Color.glowOnAccent)
                .padding(.horizontal, GlowSpacing.md)
                .frame(minHeight: 32)
                .background(pill == .waiting ? Color.glowSurfaceRaised : Color.glowAccent, in: Capsule())
                .blindBreathing(pill == .waiting)
        }
        .buttonStyle(BlindPressStyle())
        .frame(minHeight: GlowSize.minimumTapTarget)
        .accessibilityLabel(
            pill == .revealed ? Text("See who they are") : pill == .waiting ? Text("Waiting for them to reveal") : Text("Reveal"),
        )
        .accessibilityIdentifier("blind.chat.reveal")
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GlowSpacing.xxs) {
                    introNote
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        let previous = index > 0 ? model.rows[index - 1] : nil
                        if showsTime(row, after: previous) {
                            Text(row.at.formatted(date: .omitted, time: .shortened))
                                .glowFont(.caption)
                                .foregroundStyle(.glowTextSecondary)
                                .padding(.top, GlowSpacing.md)
                        }
                        BlindBubble(row: row, groupedWithPrevious: previous?.mine == row.mine && !showsTime(row, after: previous)) {
                            Task { await model.retry(row.id) }
                        } onDiscard: {
                            model.discard(row.id)
                        }
                        .id(row.id)
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                    }
                    Rectangle().fill(.glowClear).frame(height: 1)
                        .id("bottom")
                        .onAppear {
                            model.atBottom = true
                            model.scrolledToBottom()
                        }
                        .onDisappear { model.atBottom = false }
                }
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.vertical, GlowSpacing.md)
                .animation(BlindMotion.motion(BlindMotion.snappy, reduceMotion: reduceMotion), value: model.rows.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("blind.chat.messages")
            .onChange(of: model.rows.last?.id) { _, _ in
                if model.atBottom || model.rows.last?.mine == true {
                    withAnimation(BlindMotion.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: composerFocused) { _, focused in
                if focused {
                    withAnimation(BlindMotion.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .overlay(alignment: .bottom) {
                if model.newBelow > 0 {
                    Button {
                        withAnimation(BlindMotion.smooth) { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Text(model.newBelow == 1 ? String(localized: "1 new message") : String(localized: "\(model.newBelow) new messages"))
                            .glowFont(.caption)
                            .foregroundStyle(.glowOnAccent)
                            .padding(.horizontal, GlowSpacing.md)
                            .padding(.vertical, GlowSpacing.xs)
                            .background(.glowAccent, in: Capsule())
                    }
                    .padding(.bottom, GlowSpacing.sm)
                    .transition(.opacity)
                }
            }
            .animation(BlindMotion.fade, value: model.newBelow)
        }
    }

    private var introNote: some View {
        VStack(spacing: GlowSpacing.xs) {
            Text(model.isRevealed ? "You both said yes" : "Blind chat")
                .font(BlindType.codename)
                .foregroundStyle(.glowTextSecondary)
            Text(
                model.isRevealed
                    ? "You liked each other's photos, then you both tapped Reveal."
                    : "You liked each other's photos. Names and faces stay hidden until you both tap Reveal.",
            )
            .glowFont(.footnote)
            .foregroundStyle(.glowTextSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, GlowSpacing.xl)
        .padding(.horizontal, GlowSpacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// A time label before the first message and after a gap of 10 minutes or more.
    private func showsTime(_ row: BlindChatRow, after previous: BlindChatRow?) -> Bool {
        guard let previous else { return true }
        return row.at.timeIntervalSince(previous.at) >= 600
    }
}

// MARK: - Composer

extension BlindChatContent {
    private var composer: some View {
        @Bindable var model = model
        return VStack(spacing: GlowSpacing.xxs) {
            if let error = model.errorText {
                Text(error)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("blind.chat.error")
            }
            HStack(alignment: .bottom, spacing: GlowSpacing.xs) {
                TextField("Message", text: $model.draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .focused($composerFocused)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextPrimary)
                    .padding(.horizontal, GlowSpacing.md)
                    .padding(.vertical, GlowSpacing.sm)
                    .blindGlass(cornerRadius: 22)
                    .accessibilityIdentifier("blind.chat.input")
                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .glowFont(.headline)
                        .foregroundStyle(model.canSend ? Color.glowOnAccent : Color.glowTextSecondary)
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                        .background(model.canSend ? Color.glowAccent : Color.glowSurfaceRaised, in: Circle())
                }
                .buttonStyle(BlindPressStyle())
                .disabled(!model.canSend)
                .accessibilityLabel(Text("Send"))
                .accessibilityIdentifier("blind.chat.send")
            }
            if model.draft.count > 900 {
                Text("\(model.draft.count)/1000")
                    .glowFont(.caption)
                    .foregroundStyle(model.draft.count > 1000 ? .glowDanger : .glowTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, GlowSpacing.md)
        .padding(.vertical, GlowSpacing.xs)
    }

    private var leftBanner: some View {
        VStack(spacing: GlowSpacing.xxs) {
            Text("They left this chat.")
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
            Text("You can still read what was said.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(GlowSpacing.lg)
        .background(.glowSurface)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blind.chat.left")
    }
}
