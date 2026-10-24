import APIClient
import AppCore
import DesignSystem
import Foundation

// Owner: C3. Stand-ins for previews and tests: a glow client that never touches the network, and a
// Live Activity controller that does nothing.

extension GlowSession {
    /// A glow that started two minutes ago. Test data only.
    static func preview(
        hue: GlowHue = .aqua,
        word: String = "lantern",
        spot: String? = "Water station",
        status: Status = .active,
        youMet: Bool = false,
        theyMet: Bool = false,
        now: Date = Date(),
    ) -> GlowSession {
        GlowSession(
            id: "453803c0-4199-465b-a12d-1981639daadd",
            status: status,
            hue: hue,
            codeWord: word,
            meetingSpot: spot,
            startedAt: now.addingTimeInterval(-120),
            endsAt: now.addingTimeInterval(780),
            endedAt: status == .active ? nil : now,
            youMet: youMet || status == .met,
            theyMet: theyMet || status == .met,
        )
    }
}

/// Answers every call with the session it was given.
final class PreviewGlowClient: GlowClient {
    let session: GlowSession

    init(_ session: GlowSession) {
        self.session = session
    }

    func glow(for _: MatchID) async throws(APIError) -> GlowSession {
        session
    }

    func markMet(_: MatchID) async throws(APIError) -> GlowSession {
        var met = session
        met.youMet = true
        return met
    }

    func end(_: MatchID, as _: GlowEnding) async throws(APIError) -> GlowSession {
        var ended = session
        ended.status = .canceled
        ended.endedAt = Date()
        return ended
    }
}

/// Does nothing: previews and snapshots never start a real Live Activity.
@MainActor
final class NoopGlowLiveActivities: GlowLiveActivities {
    func show(_: GlowSession, at _: Date) async {}
    func end(_: GlowSession, at _: Date) async {}
    func endFinished(at _: Date, keeping _: String?) async {}
}

extension GlowModel {
    /// A model showing `session`, for previews.
    static func preview(_ session: GlowSession) -> GlowModel {
        GlowModel(
            matchID: MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a"),
            client: PreviewGlowClient(session),
            liveActivities: NoopGlowLiveActivities(),
            analytics: NoopAnalytics(),
        )
    }
}
