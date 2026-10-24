import AppCore
import DesignSystem
import SwiftUI

// Owner: C3. The glow: both screens in the same color, with the same code word and meeting spot,
// at full brightness, counting down 15 minutes. The app shows `GlowView(matchID:)` full screen for
// `.glow`.

/// The full-screen glow for one match. FeatureMatch only passes the match ID; this refetches the
/// glow itself.
public struct GlowView: View {
    public let matchID: MatchID
    @Environment(\.dependencies) private var dependencies

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        GlowScreen(
            model: GlowModel(
                matchID: matchID,
                client: LiveGlowClient(api: dependencies.api),
                liveActivities: ActivityKitGlowLiveActivities(),
                analytics: dependencies.analytics,
            ),
            events: dependencies.realtime,
        )
    }
}

/// The glow screen for a model. Tests and previews build it with a mock client.
struct GlowScreen: View {
    @State private var model: GlowModel
    private let realtime: (any RealtimeService)?
    /// Snapshots hold the pulse and the countdown still at this moment.
    private let frozenAt: Date?

    @Environment(\.navigate) private var navigate
    @State private var confirmingEnd = false

    init(model: GlowModel, events realtime: (any RealtimeService)?, frozenAt: Date? = nil) {
        _model = State(initialValue: model)
        self.realtime = realtime
        self.frozenAt = frozenAt
    }

    var body: some View {
        content
            .onAppear { model.isVisible = true }
            .onDisappear { model.isVisible = false }
            .task {
                guard let realtime else { return }
                await model.run(events: realtime.events())
            }
            .glowHaptic(.glowPulse, trigger: model.pulses)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            GlowLoadingView()
        case let .glowing(session):
            GlowOnView(
                session: session,
                isSending: model.isSending,
                actionFailed: model.actionFailed,
                controlsScreen: model.wantsFullBrightness,
                frozenAt: frozenAt,
                onMet: { Task { await model.markMet() } },
                onSwitchToChat: { Task { await endAndOpenChat(.switchToChat) } },
                onEnd: { confirmingEnd = true },
                onHide: { navigate(.matches) },
            )
            .confirmationDialog(
                Text("End the glow for both of you?"),
                isPresented: $confirmingEnd,
                titleVisibility: .visible,
            ) {
                Button("End glow", role: .destructive) { Task { _ = await model.end(as: .cancel) } }
                Button("Switch to chat") { Task { await endAndOpenChat(.switchToChat) } }
                Button("Keep glowing", role: .cancel) {}
            } message: {
                Text("You can still talk in the chat.")
            }
        case let .ended(session):
            GlowEndedView(
                status: session.status,
                onOpenChat: { navigate(.chat(model.matchID)) },
                onClose: { navigate(.matches) },
            )
        case let .unavailable(problem):
            GlowUnavailableView(
                problem: problem,
                onRetry: { Task { await model.retry() } },
                onClose: { navigate(.matches) },
            )
        }
    }

    private func endAndOpenChat(_ ending: GlowEnding) async {
        if await model.end(as: ending) {
            navigate(.chat(model.matchID))
        }
    }
}

// MARK: - The glow itself

struct GlowOnView: View {
    let session: GlowSession
    let isSending: Bool
    let actionFailed: Bool
    let controlsScreen: Bool
    let frozenAt: Date?
    let onMet: () -> Void
    let onSwitchToChat: () -> Void
    let onEnd: () -> Void
    let onHide: () -> Void

    var body: some View {
        GlowSurface(session.hue, isPulsing: frozenAt == nil, controlsScreen: controlsScreen) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: GlowSpacing.lg) {
                        topBar
                        Spacer(minLength: GlowSpacing.md)
                        word
                        spot
                        Spacer(minLength: GlowSpacing.md)
                        actions
                    }
                    .padding(.horizontal, GlowSpacing.screenMargin)
                    .padding(.vertical, GlowSpacing.md)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: onHide) {
                Image(systemName: "chevron.down")
                    .font(.glow(.headline))
                    .frame(minWidth: GlowSize.minimumTapTarget, minHeight: GlowSize.minimumTapTarget)
            }
            .accessibilityLabel(Text("Hide glow"))
            .accessibilityHint(Text("The glow keeps going. Find it again in Matches."))
            Spacer()
            GlowCountdown(start: session.startedAt, end: session.endsAt, frozenAt: frozenAt)
        }
    }

    private var word: some View {
        VStack(spacing: GlowSpacing.xs) {
            Text("Your code word")
                .glowFont(.callout)
            GlowCodeWord(session.displayWord)
            // The color's name too, for anyone who can't tell the colors apart.
            Text("\(session.hue.name) glow")
                .glowFont(.headline)
                .accessibilityLabel(Text("Color: \(session.hue.name)"))
        }
        .multilineTextAlignment(.center)
    }

    private var spot: some View {
        VStack(spacing: GlowSpacing.sm) {
            if let meetingSpot = session.meetingSpot {
                Label {
                    Text("Meet at \(meetingSpot)")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .glowFont(.headline)
            }
            Text("Hold your phone up. They're looking for this color too.")
                .glowFont(.callout)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: GlowSpacing.sm) {
            if let note {
                Text(note)
                    .glowFont(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button(action: onMet) {
                Text(session.youMet ? "Waiting for them" : "We met")
            }
            .buttonStyle(.glowOnSurface)
            .disabled(session.youMet || isSending)
            .accessibilityHint(session.youMet ? Text("") : Text("It counts once you've both tapped it."))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: GlowSpacing.md) { secondaryButtons }
                VStack(spacing: GlowSpacing.xs) { secondaryButtons }
            }
        }
    }

    @ViewBuilder private var secondaryButtons: some View {
        Button("Switch to chat", action: onSwitchToChat)
            .glowFont(.button)
            .frame(minHeight: GlowSize.minimumTapTarget)
            .disabled(isSending)
        Button("End glow", action: onEnd)
            .glowFont(.button)
            .frame(minHeight: GlowSize.minimumTapTarget)
            .disabled(isSending)
    }

    private var note: LocalizedStringKey? {
        if actionFailed {
            return "Couldn't reach Glow. Try again."
        }
        switch (session.youMet, session.theyMet) {
        case (true, false): return "Waiting for them to tap We met too."
        case (false, true): return "They tapped We met. Tap it when you've found each other."
        default: return nil
        }
    }
}

/// Minutes and seconds left, counting down to the glow's end.
struct GlowCountdown: View {
    let start: Date
    let end: Date
    let frozenAt: Date?

    var body: some View {
        Label {
            if let frozenAt {
                Text(Self.remaining(from: frozenAt, to: end))
                    .monospacedDigit()
            } else {
                Text(timerInterval: min(start, end) ... end, countsDown: true)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "timer")
        }
        .glowFont(.headline)
        .padding(.horizontal, GlowSpacing.sm)
        .padding(.vertical, GlowSpacing.xxs)
        .overlay(Capsule().strokeBorder(lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Time left"))
    }

    /// "12:34", for a frozen snapshot.
    nonisolated static func remaining(from now: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(now).rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Before and after the glow

struct GlowLoadingView: View {
    var body: some View {
        VStack(spacing: GlowSpacing.md) {
            ProgressView()
                .tint(.glowTextSecondary)
            Text("Getting your glow ready")
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.glowBackground)
    }
}

struct GlowEndedView: View {
    let status: GlowSession.Status
    let onOpenChat: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            GlowEmptyState(systemImage: icon, title: title, message: message) {
                Button("Open chat", action: onOpenChat)
                    .buttonStyle(.glowPrimary)
                Button("Back to matches", action: onClose)
                    .buttonStyle(.glowQuiet)
            }
            .padding(.top, GlowSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.glowBackground)
    }

    private var icon: String {
        switch status {
        case .met: "sparkles"
        case .canceled: "moon.stars"
        case .expired, .active: "hourglass"
        }
    }

    private var title: LocalizedStringKey {
        switch status {
        case .met: "You found each other."
        case .canceled: "The glow has ended."
        case .expired, .active: "Time's up."
        }
    }

    private var message: LocalizedStringKey {
        switch status {
        case .met: "The chat stays open."
        case .canceled: "You can still talk in the chat."
        case .expired, .active: "No rush. The chat is still open."
        }
    }
}

struct GlowUnavailableView: View {
    let problem: GlowModel.Problem
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            GlowEmptyState(systemImage: icon, title: title, message: message) {
                if problem != .gone {
                    Button("Try again", action: onRetry)
                        .buttonStyle(.glowPrimary)
                }
                Button("Back to matches", action: onClose)
                    .buttonStyle(problem == .gone ? .glowPrimary : .glowQuiet)
            }
            .padding(.top, GlowSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.glowBackground)
    }

    private var icon: String {
        switch problem {
        case .gone: "moon.stars"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.circle"
        }
    }

    private var title: LocalizedStringKey {
        switch problem {
        case .gone: "This glow has ended."
        case .offline: "Can't reach Glow right now."
        case .failed: "Something went wrong."
        }
    }

    private var message: LocalizedStringKey {
        switch problem {
        case .gone: "Your matches are where you left them."
        case .offline: "Check your connection and try again."
        case .failed: "Try again in a moment."
        }
    }
}

// MARK: - Previews

#Preview("Glowing") {
    GlowScreen(model: .preview(.preview()), events: PreviewRealtimeService())
}

#Preview("They met") {
    GlowScreen(model: .preview(.preview(hue: .sun, theyMet: true)), events: PreviewRealtimeService())
}

#Preview("Ended") {
    GlowScreen(model: .preview(.preview(status: .met)), events: PreviewRealtimeService())
}
