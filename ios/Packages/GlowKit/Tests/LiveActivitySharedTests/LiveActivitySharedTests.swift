import Foundation
import Testing
@testable import LiveActivityShared

// Owner: C3. The Live Activity's data and what the lock screen says at each moment.
struct LiveActivitySharedTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var end: Date {
        start.addingTimeInterval(900)
    }

    var attributes: GlowActivityAttributes {
        GlowActivityAttributes(
            glowID: "453803c0-4199-465b-a12d-1981639daadd",
            color: "aqua",
            codeWord: "lantern",
            meetingSpot: "Water station",
            startedAt: start,
        )
    }

    func display(_ phase: GlowActivityPhase, at seconds: TimeInterval, isStale: Bool = false) -> GlowActivityDisplay {
        GlowActivityDisplay(
            attributes: attributes,
            state: .init(phase: phase, endsAt: end),
            now: start.addingTimeInterval(seconds),
            isStale: isStale,
        )
    }

    @Test func contentStateRoundTrips() throws {
        let state = GlowActivityAttributes.ContentState(phase: .theyMet, endsAt: end)
        let decoded = try JSONDecoder().decode(
            GlowActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state),
        )
        #expect(decoded == state)
    }

    @Test func attributesHoldNoNameOrUserID() throws {
        // P1 and P6: the lock screen only ever has the color, the word, the spot and the time.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any]
        #expect(Set(json?.keys.map(\.self) ?? []) == ["glowID", "color", "codeWord", "meetingSpot", "startedAt"])
    }

    @Test func whileOnItCountsDownAndSaysWhereToMeet() {
        let shown = display(.glowing, at: 60)
        #expect(shown.codeWord == "LANTERN")
        #expect(shown.color == "aqua")
        #expect(shown.headline == "Find each other")
        #expect(shown.detail == "Meet at Water station")
        #expect(shown.showsCountdown)
        #expect(shown.countdown == start ... end)
        #expect(shown.phase == .glowing)
    }

    @Test func withoutAMeetingSpotItSaysToLookForTheColor() {
        var noSpot = attributes
        noSpot.meetingSpot = nil
        let shown = GlowActivityDisplay(attributes: noSpot, state: .init(phase: .glowing, endsAt: end), now: start, isStale: false)
        #expect(shown.detail == "Look for this color")
    }

    @Test func endsOnTimeEvenIfTheAppNeverWakesUp() {
        // One second before the end it still counts down; at the end it reads as over.
        #expect(display(.glowing, at: 899).phase == .glowing)
        let atEnd = display(.glowing, at: 900)
        #expect(atEnd.phase == .expired)
        #expect(atEnd.headline == "Time's up")
        #expect(!atEnd.showsCountdown)
        // The system marking it stale (at the stale date, endsAt) does the same.
        #expect(display(.youMet, at: 600, isStale: true).phase == .expired)
    }

    @Test func anEndingTheAppReportedWinsOverTheClock() {
        #expect(display(.met, at: 950).phase == .met)
        #expect(display(.met, at: 950).headline == "You found each other")
        #expect(display(.canceled, at: 100).headline == "The glow has ended")
        #expect(display(.canceled, at: 100).detail == "The chat is still open.")
    }

    @Test(arguments: GlowActivityPhase.allCases)
    func everyPhaseHasWords(_ phase: GlowActivityPhase) {
        let shown = display(phase, at: 10)
        #expect(!shown.headline.isEmpty)
        #expect(shown.showsCountdown == !phase.isOver)
    }

    @Test func progressRunsFromStartToEnd() {
        let shown = display(.glowing, at: 0)
        #expect(shown.progress(at: start) == 0)
        #expect(shown.progress(at: start.addingTimeInterval(450)) == 0.5)
        #expect(shown.progress(at: end.addingTimeInterval(60)) == 1)
    }
}
