import AppCore
import Foundation
import Testing
@testable import FeatureDeck

@MainActor
struct DeckModelTests {
    func model(_ service: FixtureDeckService, analytics: RecordingAnalytics = RecordingAnalytics()) -> DeckModel {
        DeckModel(roomID: testRoom, service: service, analytics: analytics, refreshInterval: .zero, now: { testNow })
    }

    func room(_ count: Int = 24, scenario: FixtureDeckService.Scenario = .normal) -> FixtureDeckService {
        FixtureDeckService(count: count, scenario: scenario, now: { testNow })
    }

    // MARK: What did you notice

    /// C1-D1: nothing is fetched (no views spent) until the person says what they noticed, or skips.
    @Test func opensWhatDidYouNoticeFirstAndFetchesNothing() async {
        let service = room()
        let deck = model(service)
        await deck.start(showMe: [.woman, .man])
        #expect(deck.isNoticeSheetOpen)
        #expect(deck.phase == .choosing)
        #expect(await service.deckRequests == 0)
        #expect(deck.tapsLeftToday == 3)
        #expect(deck.showMe == [.woman, .man])
    }

    @Test func skippingShowsEveryoneWhoFitsMe() async {
        let deck = model(room())
        await deck.start(showMe: nil)
        await deck.apply(.none)
        #expect(deck.phase == .loaded)
        #expect(deck.cards.count == 10)
        #expect(deck.hasMore)
        #expect(!deck.isNoticeSheetOpen)
    }

    @Test func gendersOutsideShowMeAreNeverSent() async {
        let deck = model(room())
        await deck.start(showMe: [.man])
        var noticed = NoticedFilters()
        noticed.genders = [.woman, .man]
        await deck.apply(noticed)
        #expect(deck.filters.genders == [.man])
    }

    // MARK: Paging

    @Test func loadsMorePagesThenSaysWhatsLeft() async {
        let deck = model(room(24))
        await deck.apply(.none)
        await deck.loadMore()
        await deck.loadMore()
        #expect(deck.cards.count == 24)
        #expect(!deck.hasMore)
        #expect(deck.viewsLeftToday == 26)
        #expect(Set(deck.cards.map(\.id)).count == 24)
    }

    @Test func pullToRefreshKeepsTheSamePagesAndOrder() async {
        let deck = model(room(24))
        await deck.apply(.none)
        await deck.loadMore()
        let before = deck.cards.map(\.id)
        await deck.refresh()
        #expect(deck.cards.map(\.id) == before)
    }

    // MARK: Empty states

    @Test(arguments: [
        (FixtureDeckService.Scenario.quiet, DeckEmptyReason.quiet),
        (.checkinEnded, .checkinEnded),
        (.paused, .paused),
        (.viewLimitReached, .viewLimitReached),
    ])
    func emptyStates(_ scenario: FixtureDeckService.Scenario, _ reason: DeckEmptyReason) async {
        let deck = model(room(scenario: scenario))
        await deck.apply(.none)
        #expect(deck.phase == .empty(reason))
    }

    @Test func nobodyFitsTheFilters() async {
        let deck = model(room(4))
        var noticed = NoticedFilters()
        noticed.topColors = [.green]
        noticed.extras = [.glasses, .hat, .beard, .headphones, .backpack]
        await deck.apply(noticed)
        #expect(deck.phase == .empty(.noMatch))
    }

    @Test func beingVisibleAgainBringsTheDeckBack() async {
        let service = room(scenario: .paused)
        let deck = model(service)
        await deck.apply(.none)
        #expect(await deck.becomeVisible())
        #expect(deck.phase == .loaded)
        #expect(await service.isPaused == false)
    }

    // MARK: Live updates (P8)

    /// Someone pauses, leaves or blocks: `deck.changed` refetches and their card is gone, and if it
    /// was open, it closes.
    @Test func deckChangedDropsADepartedCard() async throws {
        let service = room(24)
        let deck = model(service)
        await deck.apply(.none)
        let departed = try #require(deck.cards.dropFirst(3).first?.id)
        deck.open(departed)
        deck.requestTap(departed)

        await service.remove(departed)
        deck.deckChanged()
        await deck.settle()

        #expect(!deck.cards.contains { $0.id == departed })
        #expect(deck.enlarged == nil)
        #expect(deck.confirming == nil)
        #expect(deck.toast?.text == DeckCopy.cardGone)
        #expect(deck.cards.count == 10)
    }

    @Test func deckChangedRefetchesEveryPageShowing() async throws {
        let service = room(24)
        let deck = model(service)
        await deck.apply(.none)
        await deck.loadMore()
        let departed = try #require(deck.cards.last?.id)
        await service.remove(departed)
        deck.deckChanged()
        await deck.settle()
        #expect(!deck.cards.contains { $0.id == departed })
        #expect(deck.cards.count == 20)
    }

    @Test func aBurstOfEventsCostsOneRefetchAtATime() async {
        let service = room(8)
        let deck = DeckModel(roomID: testRoom, service: service, refreshInterval: .milliseconds(50), now: { testNow })
        await deck.apply(.none)
        let before = await service.deckRequests
        for _ in 0 ..< 10 {
            deck.deckChanged()
        }
        await deck.settle()
        // One refetch for the burst, and at most one more for events that came in during it.
        let made = await service.deckRequests - before
        #expect((1 ... 2).contains(made))
    }

    @Test func nothingRefetchesBeforeTheDeckIsChosen() async {
        let service = room()
        let deck = model(service)
        deck.deckChanged()
        await deck.settle()
        #expect(await service.deckRequests == 0)
    }

    @Test func aRefreshKeepsPhotoLinksThatAreStillGood() async throws {
        let clock = TestClock(testNow)
        let service = FixtureDeckService(count: 4, now: { clock.now })
        let deck = DeckModel(roomID: testRoom, service: service, refreshInterval: .zero, now: { clock.now })
        await deck.apply(.none)
        let first = try #require(deck.cards.first)
        clock.advance(10)
        await deck.refresh()
        #expect(deck.cards.first?.imageURL == first.imageURL)
        clock.advance(50)
        await deck.refresh()
        #expect(deck.cards.first?.imageURL != first.imageURL)
    }

    // MARK: Tapping

    @Test func aSentTapStaysSecretAndCountsDown() async throws {
        let analytics = RecordingAnalytics()
        let deck = model(room(), analytics: analytics)
        await deck.start(showMe: nil)
        await deck.apply(.none)
        let card = try #require(deck.cards.first { $0.id != FixtureDeckService.mutualCard })
        deck.open(card.id)
        deck.requestTap(card.id)
        #expect(deck.confirmingCard == card)

        let match = await deck.confirmTap()

        #expect(match == nil)
        #expect(deck.tapsLeftToday == 2)
        #expect(deck.cards.first { $0.id == card.id }?.tappedByMe == true)
        #expect(deck.confirming == nil)
        #expect(deck.enlarged == card.id)
        #expect(deck.toast?.text == DeckCopy.tapSent)
        #expect(analytics.events.contains { $0.name == "deck_tap" && $0.properties["result"] == "sent" })
    }

    @Test func aMutualTapHandsOffTheMatch() async {
        let deck = model(room())
        await deck.apply(.none)
        deck.open(FixtureDeckService.mutualCard)
        deck.requestTap(FixtureDeckService.mutualCard)
        let match = await deck.confirmTap()
        #expect(match == FixtureDeckService.mutualMatch)
        #expect(deck.enlarged == nil)
    }

    @Test func theFourthTapIsRefusedGently() async {
        let deck = model(room())
        await deck.apply(.none)
        let others = deck.cards.filter { $0.id != FixtureDeckService.mutualCard }.prefix(4)
        for card in others {
            deck.requestTap(card.id)
            _ = await deck.confirmTap()
        }
        #expect(deck.tapsLeftToday == 0)
        #expect(deck.toast?.text == DeckCopy.noTapsLeft)
        #expect(deck.cards.count(where: \.tappedByMe) == 3)
    }

    @Test func tappingTheSameCardAgainIsFree() async throws {
        let deck = model(room())
        await deck.apply(.none)
        let card = try #require(deck.cards.first { $0.id != FixtureDeckService.mutualCard })
        deck.requestTap(card.id)
        _ = await deck.confirmTap()
        deck.requestTap(card.id)
        _ = await deck.confirmTap()
        #expect(deck.tapsLeftToday == 2)
    }

    @Test func tappingACardThatJustLeftSaysSoAndRefetches() async throws {
        let service = room()
        let deck = model(service)
        await deck.apply(.none)
        let card = try #require(deck.cards.first { $0.id != FixtureDeckService.mutualCard })
        deck.open(card.id)
        deck.requestTap(card.id)
        await service.remove(card.id)
        _ = await deck.confirmTap()
        await deck.settle()
        #expect(deck.toast?.text == DeckCopy.cardGone)
        #expect(deck.enlarged == nil)
        #expect(!deck.cards.contains { $0.id == card.id })
    }

    // MARK: Capture (P12)

    @Test func aRecordingIsReportedOncePerCapture() async throws {
        let service = room()
        let analytics = RecordingAnalytics()
        let deck = model(service, analytics: analytics)
        await deck.apply(.none)
        let first = try #require(deck.cards.first?.id)
        deck.open(first)

        deck.captureChanged(isCaptured: true)
        deck.captureChanged(isCaptured: true)
        // Nothing stays open behind the cover.
        #expect(deck.enlarged == nil)
        deck.captureChanged(isCaptured: false)
        deck.captureChanged(isCaptured: true)
        try await waitUntil { await service.captures.count == 2 }

        #expect(await service.captures == [.recording, .recording])
        #expect(analytics.events.count { $0.name == "deck_capture" } == 2)
    }

    @Test func aScreenshotGetsAGentleNoteAndAReport() async throws {
        let service = room()
        let deck = model(service)
        deck.captureChanged(isCaptured: false)
        deck.screenshotTaken()
        try await waitUntil { await service.captures.count == 1 }
        #expect(await service.captures == [.screenshot])
        #expect(deck.toast?.text == DeckCopy.screenshotNote)
    }
}

/// Polls until `condition` holds, for work the model hands to a detached task.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
