import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: C4. The chat with one match. The app shows it for `Route.chat(matchID)`; FeatureMatch and
// FeatureGlow send people here once the chat opens, and a tapped "New message" notification does
// too (B5). Only the match ID arrives: everything else is fetched by ID.

/// The thread with one match.
public struct ChatView: View {
    public let matchID: MatchID
    @Environment(\.dependencies) private var dependencies
    @State private var model: ChatModel?

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        Group {
            if let model {
                ChatScreen(model: model)
            } else {
                ChatLoadingView()
            }
        }
        .onAppear {
            if model == nil {
                model = ChatModel(
                    matchID: matchID,
                    api: LiveChatAPI(api: dependencies.api),
                    analytics: dependencies.analytics,
                )
            }
        }
    }
}

struct ChatLoadingView: View {
    var body: some View {
        ProgressView()
            .tint(.glowAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.glowBackground)
            .accessibilityLabel(Text("Loading the chat"))
    }
}

/// The screen itself, for a model the caller owns (previews and tests build their own).
struct ChatScreen: View {
    @Bindable var model: ChatModel
    /// Off in snapshot tests, where nothing should load or listen.
    var startsByItself = true

    @Environment(\.dependencies) private var dependencies
    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingUnmatch = false
    @State private var toast: GlowToastMessage?
    @FocusState private var composerFocused: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.glowBackground)
            .navigationTitle(model.header?.firstName ?? String(localized: "Chat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { optionsMenu }
            .confirmationDialog(unmatchTitle, isPresented: $confirmingUnmatch, titleVisibility: .visible) {
                Button("Unmatch", role: .destructive) {
                    Task {
                        if await model.unmatch() {
                            navigate(.matches)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This ends the match for both of you and deletes this chat. It can't be undone.")
            }
            .glowToast($toast)
            .onChange(of: model.notice) { _, notice in
                guard let notice else { return }
                switch notice {
                case .unmatchFailed:
                    toast = GlowToastMessage(String(localized: "That didn't work. Try again in a moment."), kind: .error)
                }
                model.notice = nil
            }
            .task {
                guard startsByItself else { return }
                await model.start()
            }
            .task {
                // Subscribed alongside the first load, so nothing that arrives meanwhile is missed.
                guard startsByItself else { return }
                await model.listen(to: dependencies.realtime.events())
            }
            .onChange(of: scenePhase) { _, phase in
                // Events sent while the app was in the background never arrive: catch up.
                if phase == .active, startsByItself {
                    Task { await model.refresh() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ChatLoadingView()
        case .ready:
            ChatThread(model: model, composerFocused: $composerFocused)
        case .notOpen:
            GlowEmptyState(
                systemImage: "hourglass",
                title: "The chat isn't open yet.",
                message: "It opens once you've both chosen.",
            ) {
                Button("Back to the match") { navigate(.match(model.matchID)) }
                    .buttonStyle(.glowSecondary)
            }
            .padding(GlowSpacing.screenMargin)
        case .ended:
            GlowEmptyState(
                systemImage: "moon.stars",
                title: "This chat has ended.",
                message: "It isn't available anymore.",
            ) {
                Button("Back to matches") { navigate(.matches) }
                    .buttonStyle(.glowSecondary)
            }
            .padding(GlowSpacing.screenMargin)
        case .failed:
            GlowEmptyState(
                systemImage: "wifi.exclamationmark",
                title: "The chat didn't load.",
                message: "Check your connection, then try again.",
            ) {
                Button("Try again") { Task { await model.refresh() } }
                    .buttonStyle(.glowSecondary)
            }
            .padding(GlowSpacing.screenMargin)
        }
    }

    @ToolbarContentBuilder private var optionsMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Report", systemImage: "flag") { navigate(.report(.chat(model.matchID))) }
                Button("Block", systemImage: "hand.raised", role: .destructive) { navigate(.block(.chat(model.matchID))) }
                Button("Unmatch", systemImage: "xmark.circle", role: .destructive) { confirmingUnmatch = true }
            } label: {
                Label("Chat options", systemImage: "ellipsis.circle")
            }
            .tint(.glowTextPrimary)
            .disabled(model.phase == .ended || model.isUnmatching)
        }
    }

    private var unmatchTitle: Text {
        if let name = model.header?.firstName {
            return Text("Unmatch \(name)?")
        }
        return Text("Unmatch?")
    }
}

/// The messages and the composer.
struct ChatThread: View {
    @Bindable var model: ChatModel
    var composerFocused: FocusState<Bool>.Binding

    var body: some View {
        let rows = model.rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: GlowSpacing.xxs) {
                    if model.hasOlder {
                        ProgressView()
                            .tint(.glowAccent)
                            .padding(GlowSpacing.md)
                            .onAppear { loadOlder(keeping: rows.first?.id, proxy: proxy) }
                            .accessibilityLabel(Text("Loading earlier messages"))
                    }
                    if rows.isEmpty {
                        GlowEmptyState(
                            systemImage: "bubble.left.and.bubble.right",
                            title: "It's just the two of you here.",
                            message: "Nobody else can read this chat.",
                        )
                        .padding(.top, GlowSpacing.xxl)
                    }
                    ForEach(rows) { row in
                        VStack(spacing: GlowSpacing.xxs) {
                            if let label = row.timeLabel {
                                Text(label)
                                    .glowFont(.caption)
                                    .foregroundStyle(.glowTextSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, GlowSpacing.sm)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ChatBubble(
                                row: row,
                                otherName: model.header?.firstName ?? String(localized: "They"),
                                calendar: model.calendar,
                                onRetry: { Task { await model.retry(row.id) } },
                                onEdit: {
                                    model.edit(row.id)
                                    composerFocused.wrappedValue = true
                                },
                                onDelete: { model.discard(row.id) },
                            )
                        }
                        .padding(.top, row.continuesGroup || row.timeLabel != nil ? 0 : GlowSpacing.xs)
                        .id(row.id)
                    }
                }
                .padding(.horizontal, GlowSpacing.md)
                .padding(.vertical, GlowSpacing.sm)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: rows.last?.id) { _, last in
                guard let last else { return }
                withAnimation(GlowMotion.ui) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatComposer(
                    draft: $model.draft,
                    remaining: model.remaining,
                    canSend: model.canSend,
                    focus: composerFocused,
                    onSend: { Task { await model.send() } },
                )
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: model.outgoing.count) { old, new in new > old }
        }
    }

    private func loadOlder(keeping first: ChatMessage.ID?, proxy: ScrollViewProxy) {
        Task {
            await model.loadOlder()
            // Stay where the person was reading instead of jumping to the newly loaded top.
            if let first {
                proxy.scrollTo(first, anchor: .top)
            }
        }
    }
}

#Preview("Thread") {
    NavigationStack {
        ChatScreen(model: .preview())
    }
    .environment(\.colorScheme, .dark)
}

#Preview("Empty") {
    NavigationStack {
        ChatScreen(model: .preview(thread: []))
    }
}

extension ChatModel {
    /// A model on made-up data, for previews.
    static func preview(thread: [ChatMessage] = PreviewChatAPI.sampleThread) -> ChatModel {
        ChatModel(matchID: PreviewChatAPI.sampleMatch, api: PreviewChatAPI(thread: thread))
    }
}
