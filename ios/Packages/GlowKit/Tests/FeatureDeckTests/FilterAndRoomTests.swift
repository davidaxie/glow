import AppCore
import Foundation
import Testing
@testable import FeatureDeck

struct NoticedFiltersTests {
    @Test func emptyMeansAny() {
        let none = NoticedFilters.none
        #expect(none.isEmpty)
        #expect(none.contract == .init())
        #expect(none.matches(CardTags(topColor: .red, extras: []), gender: .man))
    }

    @Test func eachPartIsAnyOfAndExtrasAreAllOf() {
        var filters = NoticedFilters()
        filters.topColors = [.green, .blue]
        filters.extras = [.glasses]
        let green = CardTags(topColor: .green, hairLength: .short, extras: [.glasses, .hat])
        #expect(filters.matches(green, gender: .woman))
        #expect(!filters.matches(CardTags(topColor: .green, extras: []), gender: .woman))
        #expect(!filters.matches(CardTags(topColor: .red, extras: [.glasses]), gender: .woman))
        #expect(filters.partsPicked == 2)
        #expect(filters.count == 3)
    }

    /// D25: a card without a hair tag doesn't match a hair filter.
    @Test func aHairFilterSkipsCardsWithoutHair() {
        var filters = NoticedFilters()
        filters.hairLengths = [.short]
        #expect(!filters.matches(CardTags(topColor: .black, extras: [.hat]), gender: .man))
    }

    @Test func showMeLimitsTheGenderFilter() {
        var filters = NoticedFilters()
        filters.genders = [.woman, .nonbinary]
        #expect(filters.limited(toShowMe: [.woman]).genders == [.woman])
    }
}

@MainActor
struct RoomHomeModelTests {
    @Test func loadsTheRoomAndMyCheckin() async throws {
        let model = RoomHomeModel(roomID: testRoom, service: FixtureDeckService(now: { testNow }))
        await model.load()
        let snapshot = try #require(model.snapshot)
        #expect(snapshot.name == "Glow demo room (test data)")
        #expect(snapshot.isCheckedIn(at: testNow))
        #expect(snapshot.tapsLeftToday == 3)
    }

    @Test func pausingAndResuming() async {
        let service = FixtureDeckService(now: { testNow })
        let model = RoomHomeModel(roomID: testRoom, service: service)
        #expect(await model.setVisible(false))
        #expect(model.paused)
        #expect(await service.isPaused)
        // Asking for the state it's already in does nothing.
        #expect(await !model.setVisible(false))
        #expect(await model.setVisible(true))
        #expect(!model.paused)
    }

    @Test func leaving() async {
        let service = FixtureDeckService(now: { testNow })
        let analytics = RecordingAnalytics()
        let model = RoomHomeModel(roomID: testRoom, service: service, analytics: analytics)
        #expect(await model.leave())
        #expect(await service.leftRoom)
        #expect(analytics.events.map(\.name) == ["room_left"])
    }

    @Test func aFailedLoadSaysSo() async {
        let transport = RecordingTransport(["getRoomState": .init(status: 500, json: #"{"error":{"code":"internal","message":"x"}}"#)])
        let model = RoomHomeModel(roomID: testRoom, service: APIDeckService(api: api(transport)))
        await model.load()
        #expect(model.phase == .failed(.unexpected))
    }

    @Test func timeLeftReadsNaturally() {
        #expect(DeckCopy.timeLeft(2 * 3600 + 41 * 60) == "2 h 41 min left")
        #expect(DeckCopy.timeLeft(3 * 3600) == "3 h left")
        #expect(DeckCopy.timeLeft(14 * 60 + 5) == "15 min left")
        #expect(DeckCopy.tapsLeft(1) == "1 tap left today")
    }

    @Test func cardsAreDescribedByTheirTagsOnly() {
        let tags = CardTags(topColor: .green, hairLength: .short, hairColor: .blonde, extras: [.headphones, .glasses])
        #expect(DeckCopy.describe(tags) == "Green top, short blonde hair, glasses, headphones")
    }
}

/// The made-up room has to behave like the real one for the other tests to mean anything.
struct FixtureRoomTests {
    @Test func theSameSeedMakesTheSameRoom() {
        let first = FixtureDeckService.makePeople(count: 200, seed: 26)
        let second = FixtureDeckService.makePeople(count: 200, seed: 26)
        #expect(first == second)
        #expect(Set(first.map(\.card)).count == 200)
    }

    @Test func exactlyOneCardHasTheTargetLook() {
        let people = FixtureDeckService.makePeople(count: 200, seed: 26)
        var filters = NoticedFilters()
        filters.topColors = [.green]
        filters.hairLengths = [.short]
        filters.hairColors = [.blonde]
        filters.extras = [.glasses, .headphones]
        #expect(people.count { filters.matches($0.tags, gender: $0.gender) } == 1)
    }
}
