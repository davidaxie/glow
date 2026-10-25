import AppCore
import DesignSystem
import SwiftUI

/// The blind chats, by codename, newest activity first, with the drop banner on top. Polls every 4
/// seconds while the app is in the foreground and the list is on screen.
struct BlindChatListView: View {
    let service: any BlindService

    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chats: [BlindChatSummary] = []
    @State private var dropStatus: BlindDropStatus?
    @State private var loaded = false
    @State private var failed = false
    @State private var appeared = false

    static let pollInterval: Duration = .seconds(4)

    var body: some View {
        VStack(spacing: GlowSpacing.sm) {
            if let dropStatus {
                banner(dropStatus)
            }
            if chats.isEmpty, loaded {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: GlowSpacing.sm) {
                        ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                            Button {
                                navigate(.blindChat(chat.id))
                            } label: {
                                row(chat)
                            }
                            .buttonStyle(BlindPressStyle())
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 16)
                            .animation(
                                BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion)
                                    .delay(Double(index) * BlindMotion.staggerSeconds),
                                value: appeared,
                            )
                            .accessibilityIdentifier("blind.chats.row.\(chat.codename)")
                        }
                    }
                    .padding(.bottom, GlowSpacing.md)
                }
                .refreshable { await refresh() }
            }
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .glowHaptic(.lightTap, trigger: chats.count(where: \.unread))
        // Restarts when the app comes back to the foreground and stops when the list goes away (for
        // example while a chat is open), so only one screen polls at a time.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: GlowSpacing.md) {
            Spacer()
            BlindVeilOrb(seed: "quiet", size: 88).blindBreathing()
            Text(failed ? String(localized: "Couldn't load your chats.") : String(localized: "No chats yet."))
                .font(BlindType.statement)
                .foregroundStyle(.glowTextPrimary)
            Text(failed ? String(localized: "Pull down to try again.") : String(localized: "Keep swiping, then open your drop."))
                .glowFont(.body)
                .foregroundStyle(.glowTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blind.chats.empty")
    }

    private func banner(_ status: BlindDropStatus) -> some View {
        let text = BlindChatRules.dropBanner(status, hasChats: !chats.isEmpty)
        let lit = status.ready && status.canDrop
        return Button {
            navigate(.blindDrop)
        } label: {
            HStack(spacing: GlowSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.glowAccent)
                    .symbolEffect(.pulse, isActive: lit && !reduceMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                    Text(text.title).glowFont(.headline).foregroundStyle(.glowTextPrimary)
                    Text(text.detail).glowFont(.footnote).foregroundStyle(.glowTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(GlowSpacing.md)
            .blindGlass(cornerRadius: 20, highlighted: lit)
        }
        .buttonStyle(BlindPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(text.title). \(text.detail)"))
        .accessibilityIdentifier("blind.chats.dropBanner")
    }

    private func row(_ chat: BlindChatSummary) -> some View {
        HStack(spacing: GlowSpacing.md) {
            BlindVeilOrb(seed: chat.codename, size: 48, drifts: chat.status == .open)
            VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                HStack(spacing: GlowSpacing.xs) {
                    Text(chat.codename)
                        .font(BlindType.codename)
                        .foregroundStyle(.glowTextPrimary)
                    if let label = BlindChatRules.statusLabel(chat.status) {
                        Text(label)
                            .glowFont(.caption)
                            .foregroundStyle(chat.status == .revealed ? .glowAccent : .glowTextSecondary)
                    }
                }
                Text(BlindChatRules.preview(chat))
                    .glowFont(.footnote)
                    .foregroundStyle(chat.unread ? .glowTextPrimary : .glowTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: GlowSpacing.xs)
            VStack(alignment: .trailing, spacing: GlowSpacing.xs) {
                if let at = chat.lastMessage?.at {
                    Text(BlindChatRules.timeText(at)).glowFont(.caption).foregroundStyle(.glowTextSecondary)
                }
                if chat.unread {
                    Circle()
                        .fill(.glowAccent)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(Text("Unread"))
                }
            }
        }
        .padding(GlowSpacing.md)
        .frame(maxWidth: .infinity)
        .blindGlass(cornerRadius: 24)
        .opacity(chat.status == .left ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
    }

    private func refresh() async {
        do throws(BlindError) {
            let fresh = try await service.chats()
            chats = fresh
            failed = false
        } catch {
            if !loaded {
                failed = true
            }
        }
        loaded = true
        if !appeared {
            appeared = true
        }
        if let status = try? await service.dropStatus() {
            dropStatus = status
        }
    }
}
