import APIClient
import AppCore
import DesignSystem
import Foundation
@testable import FeatureGlow
import LiveActivityShared

// Owner: C3. Test doubles for the glow screen. Test data only.

let testMatch = MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a")
let otherMatch = MatchID(rawValue: "5e6f7a8b-9c0d-4e1f-a2b3-c4d5e6f70819")
/// A fixed moment, so countdowns and snapshots never depend on the real clock.
let frozenNow = Date(timeIntervalSince1970: 1_793_000_000)

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date = frozenNow) {
        current = now
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Answers each call with the next scripted result, and records what was asked.
final class ScriptedGlowClient: GlowClient, @unchecked Sendable {
    enum Call: Equatable {
        case glow, markMet, end(GlowEnding)
    }

    private let lock = NSLock()
    private var glowResults: [Result<GlowSession, APIError>]
    private var metResults: [Result<GlowSession, APIError>]
    private var endResults: [Result<GlowSession, APIError>]
    private var recorded: [Call] = []

    init(
        glow: [Result<GlowSession, APIError>] = [],
        met: [Result<GlowSession, APIError>] = [],
        end: [Result<GlowSession, APIError>] = [],
    ) {
        glowResults = glow
        metResults = met
        endResults = end
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func then(glow result: Result<GlowSession, APIError>) {
        lock.withLock { glowResults.append(result) }
    }

    private func next(_ call: Call, from results: inout [Result<GlowSession, APIError>]) throws(APIError) -> GlowSession {
        let result: Result<GlowSession, APIError> = lock.withLock {
            recorded.append(call)
            // The last scripted answer repeats, like a server that hasn't changed.
            return results.count > 1 ? results.removeFirst() : (results.first ?? .failure(.notFound))
        }
        return try result.get()
    }

    func glow(for _: MatchID) async throws(APIError) -> GlowSession {
        try next(.glow, from: &glowResults)
    }

    func markMet(_: MatchID) async throws(APIError) -> GlowSession {
        try next(.markMet, from: &metResults)
    }

    func end(_: MatchID, as ending: GlowEnding) async throws(APIError) -> GlowSession {
        try next(.end(ending), from: &endResults)
    }
}

/// Records what the screen asked of the Live Activity.
@MainActor
final class RecordingLiveActivities: GlowLiveActivities {
    enum Call: Equatable {
        case show(GlowActivityPhase)
        case end(GlowActivityPhase)
        case endFinished
    }

    private(set) var calls: [Call] = []

    func show(_ session: GlowSession, at now: Date) async {
        calls.append(.show(session.activityPhase(at: now)))
    }

    func end(_ session: GlowSession, at now: Date) async {
        calls.append(.end(session.activityPhase(at: now)))
    }

    func endFinished(at _: Date, keeping _: String?) async {
        calls.append(.endFinished)
    }
}

/// Records analytics event names and properties.
final class RecordingAnalytics: Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.withLock { recorded }
    }

    var names: [String] {
        events.map(\.name)
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock { recorded.append(event) }
    }

    func record(_: any Error, context _: StaticString) {}
}

extension GlowSession {
    /// A glow at `frozenNow`: started 2 minutes ago, 13 minutes left.
    static func test(
        hue: GlowHue = .aqua,
        word: String = "lantern",
        spot: String? = "Water station",
        status: Status = .active,
        youMet: Bool = false,
        theyMet: Bool = false,
    ) -> GlowSession {
        .preview(hue: hue, word: word, spot: spot, status: status, youMet: youMet, theyMet: theyMet, now: frozenNow)
    }
}

@MainActor
struct Harness {
    let client: ScriptedGlowClient
    let activities = RecordingLiveActivities()
    let analytics = RecordingAnalytics()
    let clock: TestClock
    let model: GlowModel

    init(_ client: ScriptedGlowClient, clock: TestClock = TestClock()) {
        self.client = client
        self.clock = clock
        model = GlowModel(
            matchID: testMatch,
            client: client,
            liveActivities: activities,
            analytics: analytics,
            clock: { clock.now },
            pollInterval: .seconds(1),
        )
    }
}
