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
        GlowScreen(model: model, events: dependencies.realtime)
    }

    private var model: GlowModel {
        #if DEBUG
            if let fixture = GlowLaunchFixture.model(for: matchID, environment: dependencies.config.environment) {
                return fixture
            }
        #endif
        return GlowModel(
            matchID: matchID,
            client: LiveGlowClient(api: dependencies.glowAPI()),
            liveActivities: ActivityKitGlowLiveActivities(),
            analytics: dependencies.analytics,
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
            GlowLoadingView(frozenAt: frozenAt)
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

// MARK: - Before and after the glow

struct GlowLoadingView: View {
    /// Snapshots hold the breath still at this moment, so the loading screen draws the same every run.
    var frozenAt: Date?
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 140

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            // A breath, not a spinner: the glow is on its way.
            Group {
                if let frozenAt {
                    breath(at: frozenAt)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        breath(at: context.date)
                    }
                }
            }
            .accessibilityHidden(true)
            Text("Getting your glow ready")
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.glowBackground)
    }

    private func breath(at date: Date) -> some View {
        let wave = GlowLook.breath(at: date)
        return Circle()
            .fill(EllipticalGradient(
                colors: [GlowRGB.white.color.opacity(0.35), GlowRGB.white.color.opacity(0)],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5,
            ))
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.03 * wave)
            .opacity(0.6 + 0.4 * wave)
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
