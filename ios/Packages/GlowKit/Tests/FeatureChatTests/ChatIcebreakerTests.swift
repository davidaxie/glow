import APIClient
import AppCore
import Foundation
import Testing
@testable import FeatureChat

// Owner: C4 (CHIPS-D1). The icebreaker chips: what they say, when they're left out, when they
// show, and that tapping one only fills the composer.

struct ChatIcebreakerCopyTests {
    let match = PreviewChatAPI.sampleMatch

    @Test func glowChatGetsAllThreeChipsWithTheirWordsFilledIn() {
        let chips = ChatIcebreaker.chips(roomName: "Glow demo room", codeWord: "lantern", meetingSpot: "Water station")
        #expect(chips.map(\.id) == ["room", "word", "spot"])
        #expect(chips.map(\.text) == [
            "Hey, glad we both noticed. What brought you to Glow demo room?",
            "Are you lantern? I'm the other one.",
            "Want to find a seat at Water station?",
        ])
    }

    @Test func justChatHasNoGlowSoItGetsTheRoomChipAlone() {
        let chips = ChatIcebreaker.chips(roomName: "Glow demo room", codeWord: nil, meetingSpot: nil)
        #expect(chips.map(\.id) == ["room"])
    }

    @Test func aChipWhoseWordIsMissingIsLeftOutNeverShownWithAHole() {
        let noWord = ChatIcebreaker.chips(roomName: "Glow demo room", codeWord: nil, meetingSpot: "Water station")
        #expect(noWord.map(\.id) == ["room", "spot"])
        let noSpot = ChatIcebreaker.chips(roomName: "Glow demo room", codeWord: "lantern", meetingSpot: nil)
        #expect(noSpot.map(\.id) == ["room", "word"])
        let noRoom = ChatIcebreaker.chips(roomName: nil, codeWord: "lantern", meetingSpot: "Water station")
        #expect(noRoom.map(\.id) == ["word", "spot"])
        let nothing = ChatIcebreaker.chips(roomName: nil, codeWord: nil, meetingSpot: nil)
        #expect(nothing.isEmpty)
    }

    @Test func blankPiecesCountAsMissing() {
        let chips = ChatIcebreaker.chips(roomName: "   ", codeWord: "", meetingSpot: "\n")
        #expect(chips.isEmpty)
        let trimmed = ChatIcebreaker.chips(roomName: "  Glow demo room ", codeWord: nil, meetingSpot: nil)
        #expect(trimmed.first?.text == "Hey, glad we both noticed. What brought you to Glow demo room?")
    }

    @Test func theOnlyInterpolatedPiecesAreTheRoomTheWordAndTheSpot() {
        // Fill in sentinel values: nothing else may appear in a chip, and no chip is left with a
        // placeholder. Also no emoji, nothing about looks, and no work question.
        let chips = ChatIcebreaker.chips(roomName: "ROOM", codeWord: "WORD", meetingSpot: "SPOT")
        #expect(chips.count == 3)
        for chip in chips {
            #expect(!chip.text.contains("%") && !chip.text.contains("{") && !chip.text.contains("\\("))
            #expect(!chip.text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
            let lowered = chip.text.lowercased()
            for banned in ["working on", "outfit", "wearing", "gorgeous", "cute", "hot", "beautiful", "handsome", "where are you"] {
                #expect(!lowered.contains(banned), "\(chip.id) mentions \(banned)")
            }
        }
        let withoutPieces = chips.map { $0.text.replacingOccurrences(of: "ROOM", with: "").replacingOccurrences(of: "WORD", with: "")
            .replacingOccurrences(of: "SPOT", with: "")
        }
        #expect(withoutPieces == [
            "Hey, glad we both noticed. What brought you to ?",
            "Are you ? I'm the other one.",
            "Want to find a seat at ?",
        ])
    }

    @Test func eachChipHasAStableIDAnalyticsCanTake() {
        #expect(ChatIcebreaker.allCases.map(\.rawValue) == ["room", "word", "spot"])
        #expect(ChatIcebreaker.room.analyticsValue == "room")
        #expect(ChatIcebreaker.word.analyticsValue == "word")
        #expect(ChatIcebreaker.spot.analyticsValue == "spot")
    }

    @Test func theHeaderCarriesWhatTheChipsNeedFromTheMatch() {
        let glow = Components.Schemas.Glow(
            id: "453803c0-4199-465b-a12d-1981639daadd",
            status: .active,
            color: .aqua,
            codeWord: "maple",
            meetingSpot: .init(id: "de000000-0000-4000-8000-0000000005f3", name: "Water station"),
            startedAt: PreviewChatAPI.sampleNow,
            endsAt: PreviewChatAPI.sampleNow.addingTimeInterval(900),
            youMet: false,
            theyMet: false,
        )
        let detail = Components.Schemas.MatchDetail(
            id: match.rawValue,
            status: .glowing,
            firstName: "Sam",
            photoCount: 2,
            roomId: "de000000-0000-4000-8000-000000000001",
            roomName: "Glow demo room (test data)",
            createdAt: PreviewChatAPI.sampleNow,
            choiceDeadline: PreviewChatAPI.sampleNow,
            otherHasChosen: true,
            glow: glow,
        )
        #expect(ChatHeader(detail) == ChatHeader(
            firstName: "Sam",
            roomName: "Glow demo room (test data)",
            codeWord: "maple",
            meetingSpot: "Water station",
        ))

        var justChat = detail
        justChat.glow = nil
        let header = ChatHeader(justChat)
        #expect(header.codeWord == nil && header.meetingSpot == nil)
        #expect(header.roomName == "Glow demo room (test data)")
    }
}

@MainActor
struct ChatIcebreakerTests {
    let match = PreviewChatAPI.sampleMatch
    static let glowHeader = ChatHeader(
        firstName: "Sam",
        roomName: "Glow demo room",
        codeWord: "lantern",
        meetingSpot: "Water station",
    )
    static let justChatHeader = ChatHeader(firstName: "Sam", roomName: "Glow demo room")

    func makeModel(
        thread: [ChatMessage] = [],
        header: ChatHeader? = glowHeader,
        analytics: RecordingAnalytics = RecordingAnalytics(),
    ) -> (model: ChatModel, api: PreviewChatAPI) {
        let api = PreviewChatAPI(thread: thread, header: header)
        return (ChatModel(matchID: match, api: api, analytics: analytics, now: { PreviewChatAPI.sampleNow }), api)
    }

    // MARK: When they show

    @Test func chipsShowInAnEmptyOpenChat() async {
        let (model, _) = makeModel()
        #expect(model.icebreakers.isEmpty) // Nothing has loaded yet.
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.icebreakers.map(\.id) == ["room", "word", "spot"])
    }

    @Test func justChatShowsTheRoomChipAndNoSpot() async {
        let (model, _) = makeModel(header: Self.justChatHeader)
        await model.start()
        #expect(model.icebreakers.map(\.id) == ["room"])
    }

    @Test func noChipsWithoutAHeaderBecauseNothingCanBeFilledIn() async {
        // The header didn't load: no room name, no word, no spot.
        let bare = ChatModel(matchID: match, api: PreviewChatAPI(thread: [], firstName: nil), now: { PreviewChatAPI.sampleNow })
        await bare.start()
        #expect(bare.phase == .ready)
        #expect(bare.icebreakers.isEmpty)

        // A name alone fills in nothing either.
        let (nameOnly, _) = makeModel(header: ChatHeader(firstName: "Sam"))
        await nameOnly.start()
        #expect(nameOnly.icebreakers.isEmpty)
    }

    @Test func theyAreGoneOnceTheyHaveSentSomething() async {
        let (model, api) = makeModel()
        await model.start()
        #expect(!model.icebreakers.isEmpty)
        api.receive("Hi!")
        await model.refresh()
        #expect(model.icebreakers.isEmpty)
    }

    @Test func theyAreGoneOnceIHaveSentSomething() async {
        let (model, _) = makeModel()
        await model.start()
        model.draft = "Hello"
        await model.send()
        #expect(model.icebreakers.isEmpty)
    }

    @Test func theyAreGoneAsSoonAsMyMessageIsOnItsWayEvenIfItFails() async {
        let (model, api) = makeModel()
        await model.start()
        api.failNextSends(.offline)
        model.draft = "Hello"
        await model.send()
        #expect(model.outgoing.count == 1)
        #expect(model.icebreakers.isEmpty)
    }

    @Test func anExistingThreadNeverShowsThem() async {
        let (model, _) = makeModel(thread: PreviewChatAPI.sampleThread)
        await model.start()
        #expect(model.icebreakers.isEmpty)
    }

    @Test func aChatThatIsNotOpenOrHasEndedHasNone() async {
        let api = PreviewChatAPI(thread: [], header: Self.glowHeader)
        api.failPages(.notOpen)
        let notOpen = ChatModel(matchID: match, api: api, now: { PreviewChatAPI.sampleNow })
        await notOpen.start()
        #expect(notOpen.phase == .notOpen)
        #expect(notOpen.icebreakers.isEmpty)

        let (ended, _) = makeModel()
        await ended.start()
        #expect(await ended.unmatch())
        #expect(ended.icebreakers.isEmpty)
    }

    // MARK: Tapping

    @Test func tappingAChipFillsTheComposerAndNeverSends() async throws {
        let analytics = RecordingAnalytics()
        let (model, api) = makeModel(analytics: analytics)
        await model.start()
        let chip = try #require(model.icebreakers.first { $0.id == "word" })
        model.useIcebreaker(chip)
        #expect(model.draft == "Are you lantern? I'm the other one.")
        #expect(model.canSend) // Ready to send, but only when the person says so.
        #expect(api.sentBodies.isEmpty)
        #expect(model.outgoing.isEmpty)
        #expect(model.messages.isEmpty)
        #expect(api.messageCount == 0)
        // Still showing: nothing has been sent yet.
        #expect(model.icebreakers.count == 3)
    }

    @Test func whatIsEditedIsWhatGetsSentThroughTheNormalPath() async throws {
        let analytics = RecordingAnalytics()
        let (model, api) = makeModel(analytics: analytics)
        await model.start()
        let chip = try #require(model.icebreakers.first { $0.id == "spot" })
        model.useIcebreaker(chip)
        model.draft = "Want to find a seat at the water station? I can grab us a table."
        await model.send()
        #expect(api.sentBodies == ["Want to find a seat at the water station? I can grab us a table."])
        #expect(model.draft.isEmpty)
        #expect(model.items.map(\.body) == ["Want to find a seat at the water station? I can grab us a table."])
        #expect(model.icebreakers.isEmpty)
    }

    @Test func aChipSentAsIsLooksLikeAnyTypedMessage() async throws {
        let analytics = RecordingAnalytics()
        let (typedModel, typedAPI) = makeModel(analytics: RecordingAnalytics())
        await typedModel.start()
        typedModel.draft = "Hey, glad we both noticed. What brought you to Glow demo room?"
        await typedModel.send()

        let (model, api) = makeModel(analytics: analytics)
        await model.start()
        try model.useIcebreaker(#require(model.icebreakers.first { $0.id == "room" }))
        await model.send()

        // The same body on the wire, the same send event: nothing marks it as a chip.
        #expect(api.sentBodies == typedAPI.sentBodies)
        let sends = analytics.events.filter { $0.name == "chat_message_sent" }
        #expect(sends == [AnalyticsEvent("chat_message_sent", ["retry": false])])
        #expect(model.items.first?.delivery == .sent)
    }

    @Test func analyticsGetTheChipIDAndNeverItsText() async {
        let analytics = RecordingAnalytics()
        let (model, _) = makeModel(analytics: analytics)
        await model.start()
        for chip in model.icebreakers {
            model.useIcebreaker(chip)
        }
        let used = analytics.events.filter { $0.name == "chat_icebreaker_used" }
        #expect(used == [
            AnalyticsEvent("chat_icebreaker_used", ["chip": "room"]),
            AnalyticsEvent("chat_icebreaker_used", ["chip": "word"]),
            AnalyticsEvent("chat_icebreaker_used", ["chip": "spot"]),
        ])
        // Nothing the chips say, or the room, word or spot they say it with, appears in any event.
        for event in analytics.events {
            let text = "\(event.name) \(event.properties)"
            for secret in ["lantern", "Water station", "Glow demo room", "Sam", "noticed"] {
                #expect(!text.contains(secret), "\(event.name) carries \(secret)")
            }
            #expect(event.properties.keys.allSatisfy { $0 == "chip" || $0 == "messages" })
        }
    }

    @Test func tappingAnotherChipReplacesAChipButKeepsWhatThePersonWrote() async throws {
        let (model, _) = makeModel()
        await model.start()
        let room = try #require(model.icebreakers.first { $0.id == "room" })
        let word = try #require(model.icebreakers.first { $0.id == "word" })
        let spot = try #require(model.icebreakers.first { $0.id == "spot" })

        // A chip untouched since it was tapped gives way to the next one.
        model.useIcebreaker(room)
        model.useIcebreaker(word)
        #expect(model.draft == word.text)

        // Text the person wrote or changed stays, and the chip goes after it.
        model.draft = "Hi there."
        model.useIcebreaker(spot)
        #expect(model.draft == "Hi there. \(spot.text)")

        model.draft = ""
        model.useIcebreaker(room)
        #expect(model.draft == room.text)
    }

    @Test func aChipThatIsNoLongerShownCannotBeUsed() async throws {
        let analytics = RecordingAnalytics()
        let (model, api) = makeModel(analytics: analytics)
        await model.start()
        let chip = try #require(model.icebreakers.first)
        api.receive("Hi!")
        await model.refresh()
        model.useIcebreaker(chip)
        #expect(model.draft.isEmpty)
        #expect(!analytics.events.contains { $0.name == "chat_icebreaker_used" })
    }

    @Test func aFilledDraftStillRespectsTheLengthLimitAndBlankRules() async throws {
        let (model, _) = makeModel()
        await model.start()
        #expect(!model.canSend)
        try model.useIcebreaker(#require(model.icebreakers.first))
        #expect(model.remaining > 0)
        #expect(model.canSend)
        model.draft = "   "
        #expect(!model.canSend)
    }
}
