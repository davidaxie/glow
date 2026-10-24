import APIClient
import AppCore
import Foundation
import Observation
import os

/// The join flow, from a code or link to a join ticket:
///
/// 1. Look the room up (resolve). A wrong code, an ended room, a paused room stop here, before
///    anyone is asked for their location.
/// 2. Ask for location if needed: When In Use, and temporary full accuracy if only approximate.
/// 3. One fresh fix, up to LOCATION_FIX_TIMEOUT.
/// 4. Send it once (join). The fix isn't kept anywhere after this call (P2).
/// 5. On a pass, hand the ticket to check-in.
@MainActor
@Observable
public final class JoinModel {
    public enum Phase: Hashable, Sendable {
        case idle
        case resolving
        case checking
        case failed(JoinFailure)
        case passed(RoomID, JoinTicket, expiresAt: Date)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var room: RoomInfo?
    public let entry: RoomEntry

    @ObservationIgnored private let service: any RoomJoining
    @ObservationIgnored private let location: any LocationService
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let fixTimeout: Duration
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "rooms.join")
    @ObservationIgnored private var attempts = 0

    public init(
        entry: RoomEntry,
        service: any RoomJoining,
        location: any LocationService,
        analytics: any Analytics = NoopAnalytics(),
        now: @escaping @Sendable () -> Date = { Date() },
        fixTimeout: Duration = .seconds(GlowConstants.locationFixTimeout),
    ) {
        self.entry = entry
        self.service = service
        self.location = location
        self.analytics = analytics
        self.now = now
        self.fixTimeout = fixTimeout
    }

    /// Starts the flow once. Calling it again (the view reappearing) does nothing.
    public func startIfNeeded() async {
        guard phase == .idle else { return }
        await run(lookUp: true)
    }

    /// "Try again" on a failure screen.
    public func retry() async {
        guard case let .failed(failure) = phase else { return }
        await run(lookUp: failure.retriesLookup || room == nil)
    }

    /// A ticket that's still good, for "Continue" after coming back from check-in.
    public var liveTicket: (RoomID, JoinTicket)? {
        guard case let .passed(room, ticket, expiresAt) = phase, now() < expiresAt else { return nil }
        return (room, ticket)
    }

    private func run(lookUp: Bool) async {
        attempts += 1
        if attempts == 1 {
            analytics.track(AnalyticsEvent("room_join_started", ["via": entry.via]))
        }
        do {
            let room: RoomInfo
            if lookUp || self.room == nil {
                phase = .resolving
                room = try await service.resolve(entry)
                self.room = room
            } else if let known = self.room {
                room = known
            } else {
                throw JoinFailure.unexpected
            }
            if let closed = room.closedReason(now: now()) {
                throw closed
            }

            phase = .checking
            let authorization = await location.authorization()
            if authorization == .notDetermined || authorization == .approximate {
                _ = await location.requestAuthorization()
            }
            let fix: LocationFix
            do {
                fix = try await location.currentFix(timeout: fixTimeout)
            } catch let error as LocationError {
                throw JoinFailure(error)
            }
            let ticket = try await service.join(room.id, entry: entry, fix: fix)
            // The fix goes out of scope here and is never stored.
            let expiresAt = now().addingTimeInterval(GlowConstants.joinTicketTTL)
            phase = .passed(room.id, ticket, expiresAt: expiresAt)
            logger.info("Joined a room after \(self.attempts, privacy: .public) attempt(s)")
            analytics.track(AnalyticsEvent("room_join_passed", ["via": entry.via, "attempts": .int(attempts)]))
        } catch {
            await fail(error)
        }
    }

    private func fail(_ error: any Error) async {
        if error is CancellationError || Task.isCancelled {
            // The screen went away mid-check; start over if it comes back.
            phase = .idle
            return
        }
        var failure: JoinFailure = switch error {
        case let failure as JoinFailure: failure
        case let failure as LocationError: JoinFailure(failure)
        default: .unexpected
        }
        if failure == .roomClosed {
            // Look again, to say whether it ended or paused.
            let fresh = try? await service.resolve(entry)
            if let fresh {
                room = fresh
            }
            failure = fresh?.closedReason(now: now()) ?? .roomEnded
        }
        phase = .failed(failure)
        logger.notice("Join stopped: \(failure.name.description, privacy: .public)")
        analytics.track(AnalyticsEvent("room_join_failed", ["reason": failure.analyticsName, "attempts": .int(attempts)]))
    }
}
