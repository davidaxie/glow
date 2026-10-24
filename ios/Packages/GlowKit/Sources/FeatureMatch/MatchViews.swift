import AppCore
import DesignSystem
import SwiftUI

// The entry views the app shows for `.mutual` and `.match` (ios/Glow/Navigation/RouteDestination.swift).
// Keep these public initializers.

/// The full-screen mutual moment: two cards drift together with a haptic, then the other person's
/// first name and photos appear, with the choice under them.
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
        /// The full-screen takeover, with the cards intro and a close button.
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
            try? await Task.sleep(for: .seconds(style == .takeover ? 5.5 : 3))
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
            // B6's takeover: the accent bloom, the reveal spring, and the close button. Closing
            // keeps the match in the Matches tab.
            GlowTakeover(.bloom) {
                ZStack {
                    if introDone {
                        content.transition(.opacity)
                    } else {
                        MutualIntro { introDone = true }.transition(.opacity)
                    }
                }
                .glowAnimation(.reveal, value: introDone)
            } onClose: {
                dismiss()
            }
        case .screen:
            content
                .padding(.horizontal, GlowSpacing.screenMargin)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .tint(.glowAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Loading the match"))
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
            }
        }
    }
}

/// Photos, name and the choice, scrolling at large text sizes.
struct MatchDetails: View {
    @Bindable var model: MatchModel
    let snapshot: MatchSnapshot
    let showsHeadline: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: GlowSpacing.lg) {
                VStack(spacing: GlowSpacing.xs) {
                    if showsHeadline {
                        Text("Someone you noticed noticed you back.")
                            .glowFont(.callout)
                            .foregroundStyle(.glowTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(verbatim: snapshot.firstName)
                        .glowFont(.display)
                        .foregroundStyle(.glowTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("In \(snapshot.roomName)")
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, GlowSpacing.xl)

                MatchPhotoCarousel(model: model, snapshot: snapshot)

                ChoicePanel(model: model, snapshot: snapshot)
            }
            .padding(.bottom, GlowSpacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - The intro

/// Two cards drift together, the phone buzzes, and a soft glow blooms where they meet. Under Reduce
/// Motion the cards are already together and simply fade in.
struct MutualIntro: View {
    let onFinished: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var together = false
    @ScaledMetric(relativeTo: .largeTitle) private var cardWidth: CGFloat = 132

    var body: some View {
        VStack(spacing: GlowSpacing.xl) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [GlowPalette.accent.color.opacity(0.55), GlowPalette.accent.color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: cardWidth * 1.6,
                    ))
                    .frame(width: cardWidth * 3.2, height: cardWidth * 3.2)
                    .opacity(together ? 1 : 0)
                    .scaleEffect(together || reduceMotion ? 1 : 0.6)
                card(tilt: -1)
                card(tilt: 1)
            }
            .frame(height: cardWidth * 1.8)
            .accessibilityHidden(true)

            Text("Someone you noticed noticed you back.")
                .glowFont(.title)
                .foregroundStyle(.glowTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(together ? 1 : 0)
                .padding(.horizontal, GlowSpacing.screenMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glowHaptic(.mutual, trigger: together)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Someone you noticed noticed you back."))
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 350))
            withAnimation(GlowMotion.animation(.reveal, reduceMotion: reduceMotion)) {
                together = true
            }
            try? await Task.sleep(for: .milliseconds(1500))
            onFinished()
        }
    }

    /// One card. `tilt` is -1 for the left card and 1 for the right one.
    private func card(tilt: CGFloat) -> some View {
        let apart = !together && !reduceMotion
        return RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
            .fill(.glowSurfaceRaised)
            .overlay {
                RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
                    .strokeBorder(GlowPalette.accent.color.opacity(together ? 0.9 : 0.35), lineWidth: 1.5)
            }
            .overlay {
                Image(systemName: "sparkle")
                    .glowFont(.title)
                    .foregroundStyle(.glowAccent)
                    .opacity(together ? 1 : 0.4)
            }
            .frame(width: cardWidth, height: cardWidth * 1.4)
            .rotationEffect(.degrees(Double(tilt) * (apart ? 14 : 5)))
            .offset(x: tilt * (apart ? cardWidth * 1.1 : cardWidth * 0.18), y: apart ? 24 : 0)
            .opacity(reduceMotion && !together ? 0 : 1)
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
