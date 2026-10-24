import APIClient
import AppCore
import Foundation
import Testing
@testable import FeatureGlow

// Owner: C3. The glow screen's model: loading, We met, ending, time running out, losing the
// match, and that full brightness is only ever on while the glow is on and showing.

@MainActor
struct GlowModelTests {
    @Test func entryViewKeepsTheMatch() {
        #expect(GlowView(matchID: testMatch).matchID == testMatch)
    }

    @Test func loadsTheGlowStartsTheLiveActivityAndPulsesOnce() async {
        let h = Harness(ScriptedGlowClient(glow: [.success(.test())]))
        await h.model.refresh()
        #expect(h.model.phase == .glowing(.test()))
        #expect(h.activities.calls == [.show(.glowing)])
        #expect(h.model.pulses == 1)
        #expect(h.analytics.names == ["glow_shown"])

        // Refreshing an unchanged glow updates the activity but doesn't pulse again.
        await h.model.refresh()
        #expect(h.model.pulses == 1)
        #expect(h.activities.calls == [.show(.glowing), .show(.glowing)])
    }

    @Test func fullBrightnessOnlyWhileTheGlowIsOnAndVisible() async {
        let h = Harness(ScriptedGlowClient(glow: [.success(.test())]))
        h.model.isVisible = true
        #expect(!h.model.wantsFullBrightness) // still loading
        await h.model.refresh()
        #expect(h.model.wantsFullBrightness)
        h.model.isVisible = false // left the screen (Hide glow, or another screen on top)
        #expect(!h.model.wantsFullBrightness)
    }

    @Test func weMetCountsOnlyWhenBothTapIt() async {
        let client = ScriptedGlowClient(
            glow: [.success(.test()), .success(.test(status: .met))],
            met: [.success(.test(youMet: true))],
        )
        let h = Harness(client)
        h.model.isVisible = true
        await h.model.refresh()

        await h.model.markMet()
        #expect(h.model.phase == .glowing(.test(youMet: true)))
        #expect(h.model.wantsFullBrightness)
        #expect(h.activities.calls.last == .show(.youMet))

        // They tap it too: the next refresh (or glow.ended) ends the glow as met.
        await h.model.refresh()
        #expect(h.model.phase == .ended(.test(status: .met)))
        #expect(!h.model.wantsFullBrightness)
        #expect(h.activities.calls.last == .end(.met))
        #expect(h.analytics.events.last == AnalyticsEvent("glow_ended", ["outcome": "met"]))
    }

    @Test func theyTappingWeMetPulsesAgain() async {
        let h = Harness(ScriptedGlowClient(glow: [.success(.test()), .success(.test(theyMet: true))]))
        await h.model.refresh()
        await h.model.refresh()
        #expect(h.model.pulses == 2)
        #expect(h.activities.calls.last == .show(.theyMet))
    }

    @Test(arguments: [GlowEnding.cancel, .switchToChat])
    func endingTheGlowEndsItForBothAndTurnsBrightnessOff(_ ending: GlowEnding) async {
        let client = ScriptedGlowClient(glow: [.success(.test())], end: [.success(.test(status: .canceled))])
        let h = Harness(client)
        h.model.isVisible = true
        await h.model.refresh()
        let ended = await h.model.end(as: ending)
        #expect(ended)
        #expect(client.calls == [.glow, .end(ending)])
        #expect(h.model.phase == .ended(.test(status: .canceled)))
        #expect(!h.model.wantsFullBrightness)
        #expect(h.activities.calls.last == .end(.canceled))
    }

    @Test func endsOnTimeEvenBeforeTheServerSaysSo() async {
        let clock = TestClock()
        // The server still says active, as it would a moment before purge or a settle.
        let h = Harness(ScriptedGlowClient(glow: [.success(.test())]), clock: clock)
        h.model.isVisible = true
        await h.model.refresh()
        await h.model.tick()
        #expect(h.model.isGlowing)

        clock.advance(by: 13 * 60) // the glow's end
        await h.model.tick()
        guard case let .ended(session) = h.model.phase else {
            Issue.record("expected the glow to have ended")
            return
        }
        #expect(session.status == .expired)
        #expect(!h.model.wantsFullBrightness)
        #expect(h.activities.calls.contains(.end(.expired)))
        #expect(h.analytics.events.contains(AnalyticsEvent("glow_ended", ["outcome": "expired"])))
    }

    @Test func aMatchThatEndsStopsTheGlowAtOnce() async {
        // Unmatched or blocked: the API answers 404 for the match (P11), and the glow must stop.
        let h = Harness(ScriptedGlowClient(glow: [.success(.test()), .failure(.notFound)]))
        h.model.isVisible = true
        await h.model.refresh()
        await h.model.refresh()
        #expect(h.model.phase == .unavailable(.gone))
        #expect(!h.model.wantsFullBrightness)
        #expect(h.activities.calls.last == .end(.glowing))
    }

    @Test func offlineFirstLoadCanBeRetried() async {
        let h = Harness(ScriptedGlowClient(glow: [.failure(.offline), .success(.test())]))
        await h.model.refresh()
        #expect(h.model.phase == .unavailable(.offline))
        await h.model.retry()
        #expect(h.model.isGlowing)
    }

    @Test func aFailedTapKeepsTheGlowOnAndSaysSoQuietly() async {
        let h = Harness(ScriptedGlowClient(glow: [.success(.test())], met: [.failure(.offline)]))
        h.model.isVisible = true
        await h.model.refresh()
        await h.model.markMet()
        #expect(h.model.isGlowing)
        #expect(h.model.actionFailed)
        #expect(h.model.wantsFullBrightness)
        #expect(!h.model.isSending)
    }

    @Test func aGlowThatAlreadyEndedShowsHowItEndedWithoutPulsing() async {
        let h = Harness(ScriptedGlowClient(glow: [.success(.test(status: .expired))]))
        await h.model.refresh()
        #expect(h.model.phase == .ended(.test(status: .expired)))
        #expect(h.model.pulses == 0)
        #expect(!h.model.wantsFullBrightness)
        #expect(!h.activities.calls.contains(.show(.glowing)))
    }

    @Test func weMetAndEndDoNothingOnceItIsOver() async {
        let client = ScriptedGlowClient(glow: [.success(.test(status: .met))])
        let h = Harness(client)
        await h.model.refresh()
        await h.model.markMet()
        #expect(await h.model.end(as: .cancel) == false)
        #expect(client.calls == [.glow])
    }

    @Test func glowEndedForThisMatchRefreshesAtOnce() async throws {
        let client = ScriptedGlowClient(glow: [.success(.test())])
        let h = Harness(client)
        let realtime = PreviewRealtimeService()
        let task = Task { await h.model.run(events: realtime.events()) }
        defer { task.cancel() }
        try await waitUntil { h.model.isGlowing }

        client.then(glow: .success(.test(status: .canceled)))
        realtime.emit(RealtimeEvent(kind: .glowEnded, matchID: otherMatch)) // someone else's: ignored
        realtime.emit(RealtimeEvent(kind: .glowEnded, matchID: testMatch))
        try await waitUntil { h.model.phase == .ended(.test(status: .canceled)) }
    }

    @Test func analyticsCarryNoWordsColorsOrSpots() async {
        let client = ScriptedGlowClient(
            glow: [.success(.test())],
            met: [.success(.test(youMet: true))],
            end: [.success(.test(status: .canceled))],
        )
        let h = Harness(client)
        await h.model.refresh()
        await h.model.markMet()
        _ = await h.model.end(as: .switchToChat)
        let text = h.analytics.events.map { "\($0)" }.joined()
        #expect(!text.contains("lantern"))
        #expect(!text.contains("aqua"))
        #expect(!text.contains("Water"))
        #expect(h.analytics.names == ["glow_shown", "glow_we_met_tapped", "glow_end_tapped", "glow_ended"])
    }
}

/// Waits for a condition the model reaches asynchronously, for up to two seconds.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0 ..< 200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
