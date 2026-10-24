import AppCore
import DesignSystem
import Observation
import SwiftUI

/// The matches list: "Now" (choosing and glowing) and "Earlier" (chatting and met).
@MainActor
@Observable
public final class MatchesListModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        case failed
    }

    public private(set) var phase: Phase = .loading
    public private(set) var matches: [MatchSummary] = []

    @ObservationIgnored private let client: any MatchClient

    public init(client: any MatchClient) {
        self.client = client
    }

    public var now: [MatchSummary] {
        matches.filter(\.isNow)
    }

    public var earlier: [MatchSummary] {
        matches.filter { !$0.isNow }
    }

    public func load() async {
        do {
            matches = try await client.matches()
            phase = .loaded
        } catch {
            // Keep what's showing; only an empty first load shows the error.
            if matches.isEmpty {
                phase = .failed
            }
        }
    }

    /// Any match event can move a row between sections, add one or remove one.
    public func handle(_ event: MatchEvent) async {
        switch event.kind {
        case .created, .choice, .ended, .glowStarted, .glowEnded, .messageCreated:
            await load()
        case .recheck:
            break
        }
    }
}

/// The Matches tab. Keep this public initializer: the app shows it for `.matches`.
public struct MatchesListView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.matchClient) private var clientOverride
    @Environment(\.navigate) private var navigate
    @State private var model: MatchesListModel?

    public init() {}

    public var body: some View {
        ZStack {
            Rectangle().fill(.glowBackground).ignoresSafeArea()
            if let model {
                MatchesList(model: model) { navigate($0.route) }
                    .task { await model.load() }
                    .task {
                        let client = MatchClients.resolve(clientOverride, dependencies)
                        for await event in dependencies.matchEvents(client) {
                            await model.handle(event)
                        }
                    }
            }
        }
        .navigationTitle(Text("Matches"))
        .onAppear {
            if model == nil {
                model = MatchesListModel(client: MatchClients.resolve(clientOverride, dependencies))
            }
        }
    }
}

struct MatchesList: View {
    let model: MatchesListModel
    let open: @MainActor (MatchSummary) -> Void

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .tint(.glowAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading your matches"))
        case .failed:
            GlowEmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't load your matches.",
                message: "Check your connection and try again.",
            ) {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.glow(.secondary, size: .compact))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where model.matches.isEmpty:
            ScrollView {
                GlowEmptyState(
                    systemImage: "sparkles",
                    title: "No matches yet.",
                    message: "When someone you noticed notices you back, they'll be here.",
                )
                .padding(.top, GlowSpacing.xxl)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
        case .loaded:
            List {
                section("Now", model.now)
                section("Earlier", model.earlier)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { await model.load() }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ rows: [MatchSummary]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    Button { open(row) } label: { MatchRow(match: row) }
                        .listRowBackground(Color.glowSurface)
                }
            } header: {
                Text(title)
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextSecondary)
            }
        }
    }
}

/// One match: their initial, first name, where, and what's happening.
struct MatchRow: View {
    let match: MatchSummary
    @Environment(\.matchClockOverride) private var fixedNow
    @ScaledMetric(relativeTo: .body) private var avatar: CGFloat = 44

    var body: some View {
        HStack(spacing: GlowSpacing.sm) {
            Text(verbatim: String(match.firstName.prefix(1)).uppercased())
                .glowFont(.headline)
                .foregroundStyle(.glowAccent)
                .frame(width: avatar, height: avatar)
                .background(.glowSurfaceRaised, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                Text(verbatim: match.firstName)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextPrimary)
                status
                    .glowFont(.footnote)
                    .foregroundStyle(match.isNow ? .glowAccent : .glowTextSecondary)
                Text(verbatim: match.roomName)
                    .glowFont(.caption)
                    .foregroundStyle(.glowTextSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, GlowSpacing.xxs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(hint))
    }

    @ViewBuilder private var status: some View {
        switch match.status {
        case .choosing:
            if let fixedNow {
                choosing(at: fixedNow)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    choosing(at: context.date)
                }
            }
        case .glowing: Text("Glowing now")
        case .chatting: Text("Chat open")
        case .met: Text("You met")
        }
    }

    private func choosing(at now: Date) -> Text {
        let minutes = Int((max(0, match.choiceDeadline.timeIntervalSince(now)) / 60).rounded(.up))
        return Text("Choose in \(minutes) min")
    }

    private var hint: LocalizedStringKey {
        switch match.status {
        case .choosing: "Opens the match, to choose Find each other or Just chat."
        case .glowing: "Opens the glow."
        case .chatting, .met: "Opens the chat."
        }
    }
}

#Preview("List") {
    NavigationStack { MatchesListView() }
        .environment(\.matchClient, FixtureMatchClient(.list))
}

#Preview("Empty") {
    NavigationStack { MatchesListView() }
        .environment(\.matchClient, FixtureMatchClient(.empty))
}
