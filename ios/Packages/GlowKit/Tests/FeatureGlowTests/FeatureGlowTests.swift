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
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test())]))
        await harness.model.refresh()
        #expect(harness.model.phase == .glowing(.test()))
        #expect(harness.activities.calls == [.show(.glowing)])
        #expect(harness.model.pulses == 1)
        #expect(harness.analytics.names == ["glow_shown"])

        // Refreshing an unchanged glow updates the activity but doesn't pulse again.
        await harness.model.refresh()
        #expect(harness.model.pulses == 1)
        #expect(harness.activities.calls == [.show(.glowing), .show(.glowing)])
    }

    @Test func fullBrightnessOnlyWhileTheGlowIsOnAndVisible() async {
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test())]))
        harness.model.isVisible = true
        #expect(!harness.model.wantsFullBrightness) // still loading
        await harness.model.refresh()
        #expect(harness.model.wantsFullBrightness)
        harness.model.isVisible = false // left the screen (Hide glow, or another screen on top)
        #expect(!harness.model.wantsFullBrightness)
    }

    @Test func weMetCountsOnlyWhenBothTapIt() async {
        let client = ScriptedGlowClient(
            glow: [.success(.test()), .success(.test(status: .met))],
            met: [.success(.test(youMet: true))],
        )
        let harness = Harness(client)
        harness.model.isVisible = true
        await harness.model.refresh()

        await harness.model.markMet()
        #expect(harness.model.phase == .glowing(.test(youMet: true)))
        #expect(harness.model.wantsFullBrightness)
        #expect(harness.activities.calls.last == .show(.youMet))

        // They tap it too: the next refresh (or glow.ended) ends the glow as met.
        await harness.model.refresh()
        #expect(harness.model.phase == .ended(.test(status: .met)))
        #expect(!harness.model.wantsFullBrightness)
        #expect(harness.activities.calls.last == .end(.met))
        #expect(harness.analytics.events.last == AnalyticsEvent("glow_ended", ["outcome": "met"]))
    }

    @Test func theyTappingWeMetPulsesAgain() async {
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test()), .success(.test(theyMet: true))]))
        await harness.model.refresh()
        await harness.model.refresh()
        #expect(harness.model.pulses == 2)
        #expect(harness.activities.calls.last == .show(.theyMet))
    }

    @Test(arguments: [GlowEnding.cancel, .switchToChat])
    func endingTheGlowEndsItForBothAndTurnsBrightnessOff(_ ending: GlowEnding) async {
        let client = ScriptedGlowClient(glow: [.success(.test())], end: [.success(.test(status: .canceled))])
        let harness = Harness(client)
        harness.model.isVisible = true
        await harness.model.refresh()
        let ended = await harness.model.end(as: ending)
        #expect(ended)
        #expect(client.calls == [.glow, .end(ending)])
        #expect(harness.model.phase == .ended(.test(status: .canceled)))
        #expect(!harness.model.wantsFullBrightness)
        #expect(harness.activities.calls.last == .end(.canceled))
    }

    @Test func endsOnTimeEvenBeforeTheServerSaysSo() async {
        let clock = TestClock()
        // The server still says active, as it would a moment before purge or a settle.
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test())]), clock: clock)
        harness.model.isVisible = true
        await harness.model.refresh()
        await harness.model.tick()
        #expect(harness.model.isGlowing)

        clock.advance(by: 13 * 60) // the glow's end
        await harness.model.tick()
        guard case let .ended(session) = harness.model.phase else {
            Issue.record("expected the glow to have ended")
            return
        }
        #expect(session.status == .expired)
        #expect(!harness.model.wantsFullBrightness)
        #expect(harness.activities.calls.contains(.end(.expired)))
        #expect(harness.analytics.events.contains(AnalyticsEvent("glow_ended", ["outcome": "expired"])))
    }

    @Test func aMatchThatEndsStopsTheGlowAtOnce() async {
        // Unmatched or blocked: the API answers 404 for the match (P11), and the glow must stop.
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test()), .failure(.notFound)]))
        harness.model.isVisible = true
        await harness.model.refresh()
        await harness.model.refresh()
        #expect(harness.model.phase == .unavailable(.gone))
        #expect(!harness.model.wantsFullBrightness)
        #expect(harness.activities.calls.last == .end(.glowing))
    }

    @Test func offlineFirstLoadCanBeRetried() async {
        let harness = Harness(ScriptedGlowClient(glow: [.failure(.offline), .success(.test())]))
        await harness.model.refresh()
        #expect(harness.model.phase == .unavailable(.offline))
        await harness.model.retry()
        #expect(harness.model.isGlowing)
    }

    @Test func aFailedTapKeepsTheGlowOnAndSaysSoQuietly() async {
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test())], met: [.failure(.offline)]))
        harness.model.isVisible = true
        await harness.model.refresh()
        await harness.model.markMet()
        #expect(harness.model.isGlowing)
        #expect(harness.model.actionFailed)
        #expect(harness.model.wantsFullBrightness)
        #expect(!harness.model.isSending)
    }

    @Test func aGlowThatAlreadyEndedShowsHowItEndedWithoutPulsing() async {
        let harness = Harness(ScriptedGlowClient(glow: [.success(.test(status: .expired))]))
        await harness.model.refresh()
        #expect(harness.model.phase == .ended(.test(status: .expired)))
        #expect(harness.model.pulses == 0)
        #expect(!harness.model.wantsFullBrightness)
        #expect(!harness.activities.calls.contains(.show(.glowing)))
    }

    @Test func weMetAndEndDoNothingOnceItIsOver() async {
        let client = ScriptedGlowClient(glow: [.success(.test(status: .met))])
        let harness = Harness(client)
        await harness.model.refresh()
        await harness.model.markMet()
        #expect(await harness.model.end(as: .cancel) == false)
        #expect(client.calls == [.glow])
    }

    @Test func glowEndedForThisMatchRefreshesAtOnce() async throws {
        let client = ScriptedGlowClient(glow: [.success(.test())])
        let harness = Harness(client)
        let realtime = PreviewRealtimeService()
        let task = Task { await harness.model.run(events: realtime.events()) }
        defer { task.cancel() }
        try await waitUntil { harness.model.isGlowing }

        client.then(glow: .success(.test(status: .canceled)))
        realtime.emit(RealtimeEvent(kind: .glowEnded, matchID: otherMatch)) // someone else's: ignored
        realtime.emit(RealtimeEvent(kind: .glowEnded, matchID: testMatch))
        try await waitUntil { harness.model.phase == .ended(.test(status: .canceled)) }
    }

    @Test func analyticsCarryNoWordsColorsOrSpots() async {
        let client = ScriptedGlowClient(
            glow: [.success(.test())],
            met: [.success(.test(youMet: true))],
            end: [.success(.test(status: .canceled))],
        )
        let harness = Harness(client)
        await harness.model.refresh()
        await harness.model.markMet()
        _ = await harness.model.end(as: .switchToChat)
        let text = harness.analytics.events.map { "\($0)" }.joined()
        #expect(!text.contains("lantern"))
        #expect(!text.contains("aqua"))
        #expect(!text.contains("Water"))
        #expect(harness.analytics.names == ["glow_shown", "glow_we_met_tapped", "glow_end_tapped", "glow_ended"])
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
