import AppCore
import DesignSystem
import SwiftUI

// The entry views the app shows for `.mutual` and `.match` (ios/Glow/Navigation/RouteDestination.swift).
// Keep these public initializers.

/// The full-screen mutual moment: two points of light drift together, meet with a heartbeat and a
/// bloom, then the other person's first name and photos appear, with the choice under them.
public struct MutualMomentView: View {
    public let matchID: MatchID

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        MatchHost(matchID: matchID, style: .takeover)
    }
}

/// One match: photos, first name, and the Find each other or Just chat choice. Opened from the
/// matches list or a notification. If the match has already moved on, it forwards to the glow or
/// the chat.
public struct MatchView: View {
    public let matchID: MatchID

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        MatchHost(matchID: matchID, style: .screen)
    }
}

/// Builds the model from the environment once, feeds it events, and navigates when it says so.
struct MatchHost: View {
    enum Style {
        /// The full-screen takeover, with the lights intro and a close button.
        case takeover
        /// A screen pushed on the Matches tab.
        case screen
    }

    let matchID: MatchID
    let style: Style

    @Environment(\.dependencies) private var dependencies
    @Environment(\.matchClient) private var clientOverride
    @Environment(\.navigate) private var navigate
    @State private var model: MatchModel?

    var body: some View {
        ZStack {
            Rectangle().fill(.glowBackground).ignoresSafeArea()
            if let model {
                MatchScreen(model: model, style: style)
                    .environment(\.dependencies, MatchClients.environment(clientOverride, dependencies))
                    .task { await model.load() }
                    .task(id: model.snapshot?.choiceDeadline) { await model.watchDeadline() }
                    .task {
                        let client = MatchClients.resolve(clientOverride, dependencies)
                        for await event in dependencies.matchEvents(client) where event.matchID == matchID {
                            await model.handle(event)
                        }
                    }
                    .onChange(of: model.route) { _, route in
                        if let route {
                            navigate(route)
                        }
                    }
                    .task { await autoChooseForRecording(model) }
            }
        }
        .onAppear {
            if model == nil {
                model = MatchModel(
                    matchID: matchID,
                    client: MatchClients.resolve(clientOverride, dependencies),
                    location: MatchClients.location(clientOverride, dependencies),
                    analytics: dependencies.analytics,
                )
            }
        }
    }
}

extension MatchHost {
    /// Debug fixtures only (`-GlowMatchFixturesChoose`, C2-D9): choose by itself after a moment,
    /// so the Simulator can record the whole flow without touch. Does nothing anywhere else.
    private func autoChooseForRecording(_ model: MatchModel) async {
        #if DEBUG
            guard dependencies.config.environment == .debug, clientOverride == nil,
                  let choice = FixtureMatchClient.launchAutoChoice
            else { return }
            try? await Task.sleep(for: .seconds(style == .takeover ? 6 : 3))
            switch choice {
            case .find: await model.chooseFind()
            case .chat: await model.chooseChat()
            }
        #endif
    }
}

/// The match, in whatever state it's in.
struct MatchScreen: View {
    @Bindable var model: MatchModel
    let style: MatchHost.Style

    @Environment(\.dismiss) private var dismiss
    @State private var introDone = false

    var body: some View {
        switch style {
        case .takeover:
            // The stage: a warm dark room with one light. The light the two points became in the
            // intro rises behind the name, so the takeover reads as one continuous moment.
            MomentStage(lightRisen: introDone, onClose: { dismiss() }) {
                ZStack {
                    if introDone {
                        content.transition(.opacity)
                    } else {
                        MutualIntro { introDone = true }.transition(.opacity)
                    }
                }
                .animation(Moment.fade, value: introDone)
            }
        case .screen:
            content
                .padding(.horizontal, GlowSpacing.screenMargin)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            MomentWaitingLight(label: Text("Loading the match"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .gone:
            GlowEmptyState(
                systemImage: "moon.stars",
                title: "This match has ended.",
                message: "It's no longer available.",
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            GlowEmptyState(
                systemImage: "wifi.exclamationmark",
                title: "Couldn't open this match.",
                message: "Check your connection and try again.",
            ) {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.glow(.secondary, size: .compact))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .choosing, .sending, .waiting, .moved:
            if let snapshot = model.snapshot {
                MatchDetails(model: model, snapshot: snapshot, showsHeadline: style == .takeover)
                    .padding(.horizontal, style == .takeover ? GlowSpacing.screenMargin : 0)
            }
        }
    }
}

/// Photos, name and the choice, scrolling at large text sizes. Arrives in a 40 ms stagger.
struct MatchDetails: View {
    @Bindable var model: MatchModel
    let snapshot: MatchSnapshot
    let showsHeadline: Bool

    @Environment(\.matchClockOverride) private var frozenNow
    @State private var appeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 52

    /// Snapshot tests hold the clock still; they get the settled layout, no entrance.
    private var shown: Bool {
        appeared || frozenNow != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GlowSpacing.lg) {
                VStack(spacing: GlowSpacing.xs) {
                    if showsHeadline {
                        Text("It's mutual")
                            .momentOverline()
                            .foregroundStyle(.glowAccent)
                            .accessibilityHidden(true)
                            .momentRise(0, shown: shown)
                        Text("Someone you noticed noticed you back.")
                            .glowFont(.callout)
                            .foregroundStyle(.glowTextSecondary)
                            .multilineTextAlignment(.center)
                            .momentRise(1, shown: shown)
                    }
                    Text(verbatim: snapshot.firstName)
                        .font(Moment.serif(size: nameSize, weight: .medium))
                        .kerning(-0.5)
                        .foregroundStyle(.glowTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                        .momentRise(2, shown: shown)
                    Text("In \(snapshot.roomName)")
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                        .momentRise(3, shown: shown)
                }
                .multilineTextAlignment(.center)
                .padding(.top, showsHeadline ? GlowSpacing.xxl : GlowSpacing.lg)

                MatchPhotoCarousel(model: model, snapshot: snapshot)
                    .momentRise(4, shown: shown)

                ChoicePanel(model: model, snapshot: snapshot)
                    .momentRise(5, shown: shown)
            }
            .padding(.bottom, GlowSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onAppear { appeared = true }
    }
}

// MARK: - The stage

/// The takeover's room: warm near-black, one accent light, and a glass close button. The light
/// sits in the middle during the intro and rises behind the name once it's done.
struct MomentStage<Content: View>: View {
    let lightRisen: Bool
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GlowPalette.surface.color, GlowPalette.background.color, GlowPalette.background.color],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height)
                MomentLight(core: lightRisen ? 0.35 : 0)
                    .frame(width: side * (lightRisen ? 1.1 : 0.9), height: side * (lightRisen ? 1.1 : 0.9))
                    .position(x: proxy.size.width / 2, y: lightRisen ? -side * 0.12 : proxy.size.height * 0.4)
                    .opacity(lightRisen ? 0.75 : 0)
                    .momentBreathing(lightRisen)
            }
            .ignoresSafeArea()
            .animation(Moment.animation(Moment.gentle, reduceMotion: reduceMotion), value: lightRisen)
            .accessibilityHidden(true)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.glow(.headline))
                    .foregroundStyle(.glowTextPrimary)
                    .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(GlowPalette.textPrimary.color.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel(Text("Close"))
            .padding(.horizontal, GlowSpacing.md)
            .padding(.top, GlowSpacing.xs)
        }
    }
}

/// A waiting state that breathes instead of spinning.
struct MomentWaitingLight: View {
    let label: Text
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 120

    var body: some View {
        MomentLight(core: 0.7)
            .frame(width: size, height: size)
            .momentBreathing()
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

// MARK: - The intro

/// Two points of light drift in from the edges and meet in the middle. As they touch, the phone
/// beats twice (a heartbeat), a bloom radiates from where they met, and the line arrives in New
/// York. Under Reduce Motion the lights are already together and everything simply fades in.
struct MutualIntro: View {
    let onFinished: @MainActor () -> Void

    enum Stage: Int, Comparable {
        case dark, apart, together, spoken

        static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = Stage.dark
    @ScaledMetric(relativeTo: .largeTitle) private var orb: CGFloat = 132

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            Spacer(minLength: 0)
            GeometryReader { proxy in
                let reach = proxy.size.width / 2 + orb * 0.2
                ZStack {
                    // The bloom where they meet: once, 600 ms, then it settles into the light.
                    Circle()
                        .fill(EllipticalGradient(
                            colors: [GlowPalette.accent.color.opacity(0.55), GlowPalette.accent.color.opacity(0)],
                            center: .center,
                            startRadiusFraction: 0,
                            endRadiusFraction: 0.5,
                        ))
                        .frame(width: orb * 4, height: orb * 4)
                        .scaleEffect(stage >= .together ? 1 : (reduceMotion ? 1 : 0.2))
                        .opacity(stage >= .together ? 1 : 0)
                        .animation(reduceMotion ? Moment.fade : Moment.bloom, value: stage)

                    light(side: -1, reach: reach)
                    light(side: 1, reach: reach)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: orb * 2.6)
            .accessibilityHidden(true)

            VStack(spacing: GlowSpacing.sm) {
                Text("It's mutual")
                    .momentOverline()
                    .foregroundStyle(.glowAccent)
                    .momentRise(0, shown: stage >= .spoken)
                Group {
                    Text("Someone you noticed")
                    Text("noticed you back.")
                        .italic()
                }
                .font(Moment.serif(.largeTitle))
                .foregroundStyle(.glowTextPrimary)
                .momentRise(1, shown: stage >= .spoken)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, GlowSpacing.screenMargin)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Someone you noticed noticed you back."))
        .accessibilityAddTraits(.isHeader)
        .task { await play() }
    }

    /// One light. `side` is -1 for the left one and 1 for the right one.
    private func light(side: CGFloat, reach: CGFloat) -> some View {
        let offset: CGFloat = switch stage {
        case .dark, .apart: reduceMotion ? side * orb * 0.04 : side * reach
        case .together, .spoken: side * orb * 0.04
        }
        return MomentLight(core: stage >= .together ? 1 : 0.8)
            .frame(width: orb, height: orb)
            .scaleEffect(stage >= .together ? 1.25 : 1)
            .offset(x: offset)
            .opacity(stage == .dark ? 0 : 1)
            .blendMode(.plusLighter)
            .momentBreathing(stage >= .spoken)
    }

    private func play() async {
        if reduceMotion {
            withAnimation(Moment.fade) { stage = .together }
            GlowHaptics.shared.play(GlowMoment.mutual)
            stage = .spoken
            try? await Task.sleep(for: .milliseconds(1800))
            onFinished()
            return
        }
        withAnimation(Moment.fade) { stage = .apart }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(Moment.gentle) { stage = .together }
        // The lights touch about halfway through the spring: the heartbeat lands there.
        try? await Task.sleep(for: .milliseconds(520))
        // U1's mutual cue: the two-beat heartbeat and the chime (silent switch and Settings respected).
        GlowHaptics.shared.play(GlowMoment.mutual)
        try? await Task.sleep(for: .milliseconds(260))
        stage = .spoken
        try? await Task.sleep(for: .milliseconds(1900))
        onFinished()
    }
}

#Preview("Takeover") {
    MutualMomentView(matchID: FixtureMatchClient.revealMatch)
        .environment(\.matchClient, FixtureMatchClient(.reveal))
}

#Preview("Waiting") {
    MatchView(matchID: FixtureMatchClient.revealMatch)
        .environment(\.matchClient, FixtureMatchClient(.waiting))
}
