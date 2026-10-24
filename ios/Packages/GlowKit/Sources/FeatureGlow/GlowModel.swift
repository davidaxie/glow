import APIClient
import AppCore
import Foundation
import Observation

// Owner: C3. Everything the glow screen does, apart from drawing it.

/// The glow screen's state and actions.
///
/// - It loads the glow by match ID (FeatureMatch only passes the ID) and refetches it every
///   `pollInterval` while it's on, and at once when `glow.ended` or `glow.started` arrives, so
///   "They tapped We met" and endings show within seconds on both phones.
/// - The screen is at full brightness only while the glow is on and visible
///   (`wantsFullBrightness`); every way out (We met, End glow, Switch to chat, time running out,
///   the match ending, leaving the screen) turns it off, and the surface puts the person's own
///   brightness back.
/// - The Live Activity follows the glow: started when it shows, updated as people tap We met,
///   ended when the glow ends.
@MainActor
@Observable
public final class GlowModel {
    public enum Phase: Equatable, Sendable {
        case loading
        /// The glow is on.
        case glowing(GlowSession)
        /// It ended: met, canceled or expired. The chat is open.
        case ended(GlowSession)
        /// There's nothing to show.
        case unavailable(Problem)
    }

    public enum Problem: Equatable, Sendable {
        /// 404: the glow (or the match) is gone, or was never mine (P11).
        case gone
        /// No connection, and nothing loaded yet.
        case offline
        /// Anything else.
        case failed
    }

    public let matchID: MatchID
    public private(set) var phase: Phase = .loading
    /// A We met or End glow request is on its way.
    public private(set) var isSending = false
    /// The last tap didn't go through (offline). The screen says so quietly; the glow stays on.
    public private(set) var actionFailed = false
    /// Goes up by one for each haptic pulse: when the glow starts, and when they tap We met.
    public private(set) var pulses = 0
    /// Set by the view while it's on screen.
    public var isVisible = false

    @ObservationIgnored private let client: any GlowClient
    @ObservationIgnored private let liveActivities: any GlowLiveActivities
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored let pollInterval: Duration

    public init(
        matchID: MatchID,
        client: any GlowClient,
        liveActivities: any GlowLiveActivities,
        analytics: any Analytics,
        clock: @escaping @Sendable () -> Date = { Date() },
        pollInterval: Duration = .seconds(5),
    ) {
        self.matchID = matchID
        self.client = client
        self.liveActivities = liveActivities
        self.analytics = analytics
        self.clock = clock
        self.pollInterval = pollInterval
    }

    /// The glow, while it's on.
    public var session: GlowSession? {
        switch phase {
        case let .glowing(session), let .ended(session): session
        case .loading, .unavailable: nil
        }
    }

    public var isGlowing: Bool {
        if case .glowing = phase { true } else { false }
    }

    /// Full brightness and keep-awake: only while the glow is on and this screen shows it.
    public var wantsFullBrightness: Bool {
        isGlowing && isVisible
    }

    // MARK: Running

    /// Loads the glow, then keeps it fresh until the task is cancelled (the screen goes away).
    public func run(events: AsyncStream<RealtimeEvent>) async {
        await refresh()
        let matchID = matchID
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await event in events where event.matchID == matchID {
                    guard event.kind == .glowEnded || event.kind == .glowStarted else { continue }
                    await self?.refresh()
                }
            }
            group.addTask { [weak self, pollInterval] in
                while !Task.isCancelled {
                    // One tick a second keeps the end on time; a refetch every pollInterval.
                    var waited = Duration.zero
                    while waited < pollInterval, !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        waited += .seconds(1)
                        await self?.tick()
                    }
                    guard let self, await self.isGlowing else { continue }
                    await refresh()
                }
            }
        }
    }

    /// Fetches the glow and shows whatever it says.
    public func refresh() async {
        do {
            try await apply(client.glow(for: matchID))
        } catch {
            await handle(error, whileLoading: true)
        }
    }

    /// The clock moved on. A glow past its end is over now, even before the server says so.
    public func tick() async {
        guard case let .glowing(session) = phase, !session.isOn(at: clock()) else { return }
        var expired = session
        expired.status = .expired
        await apply(expired)
        // Let the server settle it too, so both phones hear glow.ended.
        await refresh()
    }

    // MARK: Actions

    /// We met. It counts once both have tapped it.
    public func markMet() async {
        guard isGlowing, !isSending else { return }
        isSending = true
        actionFailed = false
        defer { isSending = false }
        analytics.track(AnalyticsEvent("glow_we_met_tapped"))
        do {
            try await apply(client.markMet(matchID))
        } catch {
            await handle(error, whileLoading: false)
        }
    }

    /// End glow, or Switch to chat. Either way it ends for both and the chat opens.
    /// Returns whether it ended, so the screen can go to the chat.
    @discardableResult
    public func end(as ending: GlowEnding) async -> Bool {
        guard isGlowing, !isSending else { return false }
        isSending = true
        actionFailed = false
        defer { isSending = false }
        switch ending {
        case .cancel: analytics.track(AnalyticsEvent("glow_end_tapped", ["as": "cancel"]))
        case .switchToChat: analytics.track(AnalyticsEvent("glow_end_tapped", ["as": "switch_to_chat"]))
        }
        do {
            try await apply(client.end(matchID, as: ending))
            return !isGlowing
        } catch {
            await handle(error, whileLoading: false)
            return phase == .unavailable(.gone)
        }
    }

    /// Try again after a failed first load.
    public func retry() async {
        phase = .loading
        await refresh()
    }

    // MARK: State

    private func apply(_ session: GlowSession) async {
        let now = clock()
        let before = self.session
        let wasGlowing = isGlowing
        if session.isOn(at: now) {
            phase = .glowing(session)
            if !wasGlowing {
                pulses += 1
                analytics.track(AnalyticsEvent("glow_shown"))
            } else if session.theyMet, before?.theyMet == false {
                pulses += 1
            }
            await liveActivities.show(session, at: now)
        } else {
            var ended = session
            if ended.status == .active {
                ended.status = .expired
            }
            phase = .ended(ended)
            if wasGlowing {
                trackEnding(ended.status)
            }
            await liveActivities.end(ended, at: now)
        }
    }

    private func handle(_ error: any Error, whileLoading: Bool) async {
        let apiError = APIError(error)
        switch apiError {
        case .cancelled:
            return
        case .notFound:
            // Gone, or never mine. Stop glowing at once.
            if let session {
                await liveActivities.end(session, at: clock())
            }
            phase = .unavailable(.gone)
        case .offline, .rateLimited:
            if phase == .loading {
                phase = .unavailable(.offline)
            } else if !whileLoading {
                actionFailed = true
            }
        case .unauthorized, .unexpected:
            if phase == .loading {
                phase = .unavailable(.failed)
            } else if !whileLoading {
                actionFailed = true
            }
            analytics.record(apiError, context: "glow")
        }
    }

    private func trackEnding(_ status: GlowSession.Status) {
        switch status {
        case .met: analytics.track(AnalyticsEvent("glow_ended", ["outcome": "met"]))
        case .canceled: analytics.track(AnalyticsEvent("glow_ended", ["outcome": "canceled"]))
        case .expired: analytics.track(AnalyticsEvent("glow_ended", ["outcome": "expired"]))
        case .active: break
        }
    }
}
