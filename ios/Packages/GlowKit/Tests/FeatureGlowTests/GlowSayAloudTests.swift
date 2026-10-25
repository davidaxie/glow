import Foundation
import Testing
@testable import FeatureGlow

// Owner: C3 (CHIPS-D1). "Need an excuse?": three lines to say aloud under the code word and the
// meeting spot. Static, for reading, with only the code word and the spot filled in.

struct GlowSayAloudTests {
    @Test func threeLinesWithTheWordAndTheSpotFilledIn() {
        let lines = GlowSayAloud.lines(codeWord: "lantern", meetingSpot: "Water station")
        #expect(lines.map(\.id) == ["word", "noticed", "spot"])
        #expect(lines.map(\.text) == [
            "Are you lantern?",
            "We both noticed. Hi.",
            "Found you. Shall we sit by Water station?",
        ])
    }

    @Test func withoutAMeetingSpotTheSpotLineIsLeftOutNotShownWithAHole() {
        let lines = GlowSayAloud.lines(codeWord: "kazoo", meetingSpot: nil)
        #expect(lines.map(\.text) == ["Are you kazoo?", "We both noticed. Hi."])
        #expect(GlowSayAloud.lines(codeWord: "kazoo", meetingSpot: "  ").count == 2)
        #expect(GlowSayAloud.lines(codeWord: "kazoo", meetingSpot: "").count == 2)
    }

    @Test func aMissingWordLeavesOutItsLine() {
        let lines = GlowSayAloud.lines(codeWord: " ", meetingSpot: "Food line")
        #expect(lines.map(\.id) == ["noticed", "spot"])
    }

    @Test func theOnlyInterpolatedPiecesAreTheWordAndTheSpot() {
        let lines = GlowSayAloud.lines(codeWord: "WORD", meetingSpot: "SPOT")
        let bare = lines.map { $0.text.replacingOccurrences(of: "WORD", with: "").replacingOccurrences(of: "SPOT", with: "") }
        #expect(bare == ["Are you ?", "We both noticed. Hi.", "Found you. Shall we sit by ?"])
        for line in lines {
            #expect(!line.text.contains("%") && !line.text.contains("{"))
            #expect(!line.text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
        }
    }
}
