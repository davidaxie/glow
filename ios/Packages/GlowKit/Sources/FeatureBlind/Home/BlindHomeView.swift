import AppCore
import DesignSystem
import Observation
import SwiftUI

/// Which half of the Blind tab is showing. Shared, so the drop's "See my chats" can switch it.
@MainActor
@Observable
final class BlindTabState {
    enum Section: String, Hashable, CaseIterable {
        case swipe, chats
    }

    static let shared = BlindTabState()
    var section: Section = .swipe
}

/// Membership and the deck, kept for as long as the Blind tab lives.
@MainActor
@Observable
final class BlindHomeModel {
    enum Phase: Equatable {
        case loading
        case notMember
        case member
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var isJoining = false
    private(set) var errorText: String?
    let service: any BlindService
    let images: BlindImageStore
    let deck: BlindDeckModel
    private let analytics: any Analytics

    init(service: any BlindService, analytics: any Analytics = NoopAnalytics()) {
        self.service = service
        self.analytics = analytics
        images = BlindImageStore(service: service)
        deck = BlindDeckModel(service: service, images: images)
    }

    func load() async {
        do {
            let me = try await service.me()
            phase = me.isMember ? .member : .notMember
        } catch {
            if phase == .loading {
                phase = .failed(error.message)
            }
        }
    }

    func join() async {
        guard !isJoining else { return }
        isJoining = true
        errorText = nil
        defer { isJoining = false }
        do {
            _ = try await service.join()
            analytics.track(AnalyticsEvent("blind_joined"))
            phase = .member
        } catch {
            errorText = error.message
        }
    }

    /// Leaving deletes my Blind swipes, matches and chats.
    func leave() async -> Bool {
        do {
            try await service.leaveBlind()
            analytics.track(AnalyticsEvent("blind_left"))
            deck.reset()
            phase = .notMember
            return true
        } catch {
            errorText = error.message
            return false
        }
    }
}

/// The Blind tab: the opt-in screen until I join, then the photo-only deck and the blind chats.
public struct BlindHomeView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @State private var model: BlindHomeModel?

    public init() {}

    public var body: some View {
        ZStack {
            BlindCanvas()
            if let model {
                BlindHomeContent(model: model)
            } else {
                BlindVeilOrb(seed: "blind", size: 72).blindBreathing()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard model == nil else { return }
            let created = BlindHomeModel(service: dependencies.blindService(override: override), analytics: dependencies.analytics)
            model = created
            await created.load()
        }
    }
}

private struct BlindHomeContent: View {
    let model: BlindHomeModel
    @State private var tab = BlindTabState.shared
    @State private var confirmLeave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                BlindVeilOrb(seed: "blind", size: 72).blindBreathing()
            case .notMember:
                BlindOptInView(isJoining: model.isJoining, errorText: model.errorText) {
                    Task { await model.join() }
                }
                .transition(.opacity)
            case .member:
                member.transition(.opacity)
            case let .failed(message):
                GlowEmptyState(systemImage: "wifi.slash", title: "Blind isn't reachable", message: LocalizedStringKey(message)) {
                    Button("Try again") { Task { await model.load() } }.buttonStyle(.glowSecondary)
                }
            }
        }
        .animation(BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion), value: model.phase)
    }

    private var member: some View {
        VStack(spacing: GlowSpacing.sm) {
            header
            switch tab.section {
            case .swipe:
                BlindDeckView(model: model.deck, images: model.images)
            case .chats:
                BlindChatListView(service: model.service)
            }
        }
        .confirmationDialog("Leave Blind?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave Blind", role: .destructive) { Task { _ = await model.leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Blind swipes, matches and chats are deleted. Rooms and your profile stay as they are.")
        }
    }

    private var header: some View {
        HStack(spacing: GlowSpacing.sm) {
            Text("Blind")
                .font(BlindType.codename)
                .foregroundStyle(.glowTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: GlowSpacing.xs)
            BlindSectionPicker(selection: $tab.section)
            Menu {
                Button("Leave Blind", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLeave = true
                }
                .accessibilityIdentifier("blind.leave")
            } label: {
                Image(systemName: "ellipsis")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextSecondary)
                    .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Blind options"))
            .accessibilityIdentifier("blind.menu")
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.top, GlowSpacing.xs)
    }
}

/// Swipe | Chats, as one glass capsule with a sliding light.
private struct BlindSectionPicker: View {
    @Binding var selection: BlindTabState.Section
    @Namespace private var light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BlindTabState.Section.allCases, id: \.self) { section in
                let selected = selection == section
                Button {
                    withAnimation(BlindMotion.motion(BlindMotion.snappy, reduceMotion: reduceMotion)) {
                        selection = section
                    }
                } label: {
                    Text(section == .swipe ? "Swipe" : "Chats")
                        .glowFont(.chip)
                        .foregroundStyle(selected ? .glowOnAccent : .glowTextSecondary)
                        .padding(.horizontal, GlowSpacing.md)
                        .frame(minHeight: GlowSize.chipHeight)
                        .background {
                            if selected {
                                Capsule().fill(.glowAccent).matchedGeometryEffect(id: "light", in: light)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("blind.section.\(section.rawValue)")
            }
        }
        .padding(GlowSpacing.xxs)
        .background(.glowSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(.glowLine, lineWidth: 1))
        .glowHaptic(.selection, trigger: selection)
    }
}

/// The opt-in: what Blind is, the one privacy line that matters, and Join.
struct BlindOptInView: View {
    let isJoining: Bool
    let errorText: String?
    let onJoin: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rules: [(symbol: String, text: LocalizedStringKey)] = [
        ("photo.on.rectangle", "Swipe on photos only. No names, no bios."),
        ("moon.stars", "Mutual likes wait for the drop, then open as chats with codenames."),
        ("eye", "Names and photos show only when you both tap Reveal."),
        ("door.left.hand.open", "Either of you can leave without ever being revealed."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                ZStack {
                    BlindVeilOrb(seed: "Fox", size: 96).offset(x: -54, y: 10)
                    BlindVeilOrb(seed: "Comet", size: 72).offset(x: 58, y: -18)
                    BlindVeilOrb(seed: "Otter", size: 56).offset(x: 20, y: 48)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .blindBreathing()

                VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                    Text("Blind")
                        .font(BlindType.codenameHero)
                        .foregroundStyle(.glowTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Photos first. Names last.")
                        .font(BlindType.statement)
                        .foregroundStyle(.glowTextSecondary)
                }

                VStack(alignment: .leading, spacing: GlowSpacing.md) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.sm) {
                            Image(systemName: rule.symbol)
                                .foregroundStyle(.glowAccent)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(rule.text)
                                .glowFont(.body)
                                .foregroundStyle(.glowTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(
                            BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion).delay(Double(index) * BlindMotion.staggerSeconds),
                            value: appeared,
                        )
                    }
                }

                HStack(alignment: .top, spacing: GlowSpacing.sm) {
                    Image(systemName: "lock")
                        .foregroundStyle(.glowTextSecondary)
                        .accessibilityHidden(true)
                    Text("Your photos (never your name) are shown to other Blind members. Nothing about rooms or where you are is ever shown.")
                        .glowFont(.callout)
                        .foregroundStyle(.glowTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blind.optin.privacy")
                }
                .padding(GlowSpacing.md)
                .blindGlass(cornerRadius: 20)
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.lg)
            .padding(.bottom, GlowSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GlowSpacing.xs) {
                if let errorText {
                    Text(errorText).glowFont(.footnote).foregroundStyle(.glowDanger)
                }
                Button("Join Blind", action: onJoin)
                    .buttonStyle(.glowPrimary)
                    .glowLoading(isJoining)
                    .accessibilityIdentifier("blind.join")
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.bottom, GlowSpacing.sm)
        }
        .onAppear { appeared = true }
    }
}
