import APIClient
import AppCore
import Foundation
import Observation
import os
import UIKit

/// One match from my side: the reveal, the choice, and waiting for the other person.
///
/// The screens show it; the model decides. It never holds anything about the other person beyond
/// their first name and photo count (P1), and it only asks for photos once the match exists.
@MainActor
@Observable
public final class MatchModel {
    public enum Phase: Equatable, Sendable {
        case loading
        /// The choice window is open and I haven't chosen.
        case choosing
        /// Sending a choice (and getting a fix first, for Find).
        case sending(MatchSnapshot.Choice)
        /// I chose Find; waiting for them.
        case waiting
        /// Choosing is over: the glow or the chat. `route` says where.
        case moved(Route)
        /// The match ended, or was never mine.
        case gone
        /// Couldn't load it. Try again.
        case failed(MatchError)
    }

    /// A gentle note under the choices after something didn't work.
    public enum Notice: Equatable, Sendable {
        case notInRoom
        case locationDenied
        case locationUnavailable
        case offline
        case slowDown
        case failed
    }

    public let matchID: MatchID
    public private(set) var snapshot: MatchSnapshot?
    public private(set) var phase: Phase = .loading
    public var notice: Notice?
    /// Where to go next, set once when choosing ends. The screen sends it through `navigate`.
    public private(set) var route: Route?

    @ObservationIgnored private let client: any MatchClient
    @ObservationIgnored private let location: any LocationService
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "match")
    @ObservationIgnored private var resendingFind = false

    public init(matchID: MatchID, client: any MatchClient, location: any LocationService, analytics: any Analytics) {
        self.matchID = matchID
        self.client = client
        self.location = location
        self.analytics = analytics
    }

    // MARK: Loading

    /// Loads the match, or refreshes it.
    public func load() async {
        do {
            apply(try await client.match(matchID))
        } catch MatchError.notFound {
            becomeGone()
        } catch {
            if snapshot == nil {
                phase = .failed(error)
            }
            logger.notice("Couldn't load the match")
        }
    }

    /// Something happened to this match elsewhere (Realtime, a push, the fixtures).
    public func handle(_ event: MatchEvent) async {
        guard event.matchID == matchID else { return }
        switch event.kind {
        case .ended:
            becomeGone()
        case .recheck:
            // Both chose Find, but my location check went stale while I waited: send it again.
            await resendFind()
        case .created, .choice, .glowStarted, .glowEnded:
            await load()
        case .messageCreated:
            break
        }
    }

    /// Waits until the choice window closes, then refreshes, so the chat opens on time even if no
    /// event arrives. Returns early when cancelled.
    public func watchDeadline() async {
        while !Task.isCancelled {
            guard let snapshot, snapshot.status == .choosing else { return }
            let left = snapshot.secondsLeft(at: .now)
            // A second past the deadline, so the server has certainly applied it.
            try? await Task.sleep(for: .seconds(left + 1))
            guard !Task.isCancelled else { return }
            await load()
            if self.snapshot?.status == .choosing, self.snapshot?.secondsLeft(at: .now) == 0 {
                // The server hasn't moved it yet; try again shortly.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Choosing

    /// Find each other: a fresh location fix, then the choice.
    public func chooseFind() async {
        guard canChoose else { return }
        notice = nil
        phase = .sending(.find)
        analytics.track(AnalyticsEvent("match_choice", ["choice": "find"]))
        let fix: LocationFix
        do {
            fix = try await freshFix()
        } catch {
            show(error)
            return
        }
        await send(.find, fix: fix)
    }

    /// Just chat. Also works while waiting, to change my mind from Find.
    public func chooseChat() async {
        guard canChoose || phase == .waiting else { return }
        notice = nil
        phase = .sending(.chat)
        analytics.track(AnalyticsEvent("match_choice", ["choice": "chat"]))
        await send(.chat, fix: nil)
    }

    private var canChoose: Bool {
        phase == .choosing
    }

    private func send(_ choice: MatchSnapshot.Choice, fix: LocationFix?) async {
        do {
            let outcome = try await client.choose(choice, for: matchID, fix: fix)
            track(outcome)
            apply(outcome.match, next: outcome.next)
        } catch {
            show(error)
        }
    }

    private func resendFind() async {
        guard phase == .waiting, snapshot?.yourChoice == .find, !resendingFind else { return }
        resendingFind = true
        defer { resendingFind = false }
        do {
            let fix = try await freshFix()
            let outcome = try await client.choose(.find, for: matchID, fix: fix)
            track(outcome)
            apply(outcome.match, next: outcome.next)
        } catch {
            show(error)
        }
    }

    private func freshFix() async throws(MatchError) -> LocationFix {
        var authorization = await location.authorization()
        if authorization == .notDetermined || authorization == .approximate {
            authorization = await location.requestAuthorization()
        }
        guard authorization == .precise || authorization == .approximate else { throw .locationDenied }
        do {
            return try await location.currentFix(timeout: .seconds(GlowConstants.locationFixTimeout))
        } catch LocationError.denied {
            throw .locationDenied
        } catch {
            throw .locationInaccurate
        }
    }

    // MARK: Photos

    /// The other person's photo `index`, decoded. Only once the match has loaded, and only below
    /// its `photoCount` (P1). Held by whoever shows it, never cached.
    public func photo(_ index: Int) async -> UIImage? {
        guard let snapshot, index >= 0, index < snapshot.photoCount else { return nil }
        guard let data = try? await client.photo(matchID, index: index) else { return nil }
        return UIImage(data: data)
    }

    // MARK: State

    private func apply(_ match: MatchSnapshot, next: ChoiceOutcome.Next? = nil) {
        snapshot = match
        if let destination = match.destination ?? next.flatMap({ destination(for: $0) }) {
            phase = .moved(destination)
            if route == nil {
                route = destination
            }
        } else if match.yourChoice == .find {
            phase = .waiting
        } else if case .sending = phase {
            // A refresh arrived while a choice is on its way; the reply decides.
        } else {
            phase = .choosing
        }
    }

    private func destination(for next: ChoiceOutcome.Next) -> Route? {
        switch next {
        case .glow: .glow(matchID)
        case .chat: .chat(matchID)
        case .waiting: nil
        }
    }

    private func becomeGone() {
        phase = .gone
        notice = nil
    }

    private func show(_ error: MatchError) {
        switch error {
        case .notFound:
            becomeGone()
            return
        case .notInRoom: notice = .notInRoom
        case .locationDenied: notice = .locationDenied
        case .locationInaccurate: notice = .locationUnavailable
        case .offline: notice = .offline
        case .rateLimited: notice = .slowDown
        case .unauthorized, .failed: notice = .failed
        }
        if let snapshot {
            phase = snapshot.destination.map(Phase.moved) ?? .choosing
        } else {
            phase = .failed(error)
        }
    }

    private func track(_ outcome: ChoiceOutcome) {
        let next: AnalyticsValue = switch outcome.next {
        case .waiting: "waiting"
        case .glow: "glow"
        case .chat: "chat"
        }
        analytics.track(AnalyticsEvent("match_choice_result", ["next": next]))
    }
}
