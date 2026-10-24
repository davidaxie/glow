import APIClient
import DesignSystem
import Foundation
import LiveActivityShared
import Testing
@testable import FeatureGlow

// Owner: C3. From the API's Glow to what the screen and the lock screen show.

struct GlowSessionTests {
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    func apiGlow(
        status: Components.Schemas.GlowStatus = .active,
        color: Components.Schemas.GlowColor = .sun,
        youMet: Bool = false,
        theyMet: Bool = false,
    ) -> Components.Schemas.Glow {
        Components.Schemas.Glow(
            id: "453803c0-4199-465b-a12d-1981639daadd",
            status: status,
            color: color,
            codeWord: "pretzel",
            meetingSpot: .init(id: "de000000-0000-4000-8000-0000000005f3", name: "Food line"),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            youMet: youMet,
            theyMet: theyMet,
        )
    }

    @Test func mapsTheAPIsGlow() {
        let session = GlowSession(apiGlow())
        #expect(session.hue == .sun)
        #expect(session.displayWord == "PRETZEL")
        #expect(session.meetingSpot == "Food line")
        #expect(session.status == .active)
        #expect(session.isOn(at: start.addingTimeInterval(899)))
        #expect(!session.isOn(at: start.addingTimeInterval(900)))
    }

    @Test(arguments: Components.Schemas.GlowColor.allCases)
    func everyContractColorHasAHue(_ color: Components.Schemas.GlowColor) {
        #expect(GlowHue(rawValue: color.rawValue) != nil)
        #expect(GlowSession(apiGlow(color: color)).hue.rawValue == color.rawValue)
    }

    @Test func liveActivityPhaseFollowsTheGlow() {
        let now = start.addingTimeInterval(60)
        #expect(GlowSession(apiGlow()).activityPhase(at: now) == .glowing)
        #expect(GlowSession(apiGlow(youMet: true)).activityPhase(at: now) == .youMet)
        #expect(GlowSession(apiGlow(theyMet: true)).activityPhase(at: now) == .theyMet)
        #expect(GlowSession(apiGlow(status: .met, youMet: true, theyMet: true)).activityPhase(at: now) == .met)
        #expect(GlowSession(apiGlow(status: .canceled)).activityPhase(at: now) == .canceled)
        #expect(GlowSession(apiGlow()).activityPhase(at: start.addingTimeInterval(900)) == .expired)
    }

    @Test func theLiveActivityGetsOnlyWhatTheGlowScreenShows() {
        let attributes = GlowSession(apiGlow()).activityAttributes
        #expect(attributes.color == "sun")
        #expect(attributes.codeWord == "pretzel")
        #expect(attributes.meetingSpot == "Food line")
        #expect(attributes.glowID == "453803c0-4199-465b-a12d-1981639daadd")
        let state = GlowSession(apiGlow()).activityState(at: start)
        #expect(state.endsAt == start.addingTimeInterval(900))
    }

    @Test func frozenCountdownReadsMinutesAndSeconds() {
        #expect(GlowCountdown.remaining(from: start, to: start.addingTimeInterval(780)) == "13:00")
        #expect(GlowCountdown.remaining(from: start, to: start.addingTimeInterval(59.6)) == "0:59")
        #expect(GlowCountdown.remaining(from: start.addingTimeInterval(10), to: start) == "0:00")
    }
}
