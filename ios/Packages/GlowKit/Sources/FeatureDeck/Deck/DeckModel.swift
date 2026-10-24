import APIClient
import AppCore
import DesignSystem
import Foundation
import Observation
import os

// Owner: C1. The deck's state: what I noticed, the pages of cards, the enlarged card, tapping,
// live updates (P8) and capture reports (P12).

@MainActor
@Observable
final class DeckModel {
    enum Phase: Equatable {
        /// Waiting for What did you notice (or Skip). Nothing is fetched yet, so no views are spent
        /// on cards the person would filter out (C1-D1).
        case choosing
        case loading
        case loaded
        case empty(DeckEmptyReason)
        case failed(DeckFailure)
    }

    let roomID: RoomID
    private(set) var phase: Phase = .choosing
    private(set) var cards: [DeckCard] = []
    private(set) var filters: NoticedFilters = .none
    /// Genders I may filter by: my show me, in a stable order.
    private(set) var showMe: [Gender] = Gender.allCases
    private(set) var viewsLeftToday: Int?
    private(set) var tapsLeftToday: Int?
    /// The room's slug, for Check in again.
    private(set) var roomSlug: String?
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    private(set) var isTapping = false
    var isNoticeSheetOpen = false
    /// The enlarged card, if one is open.
    var enlarged: CardID?
    /// The card waiting for "That's them?" to be confirmed.
    var confirming: CardID?
    var toast: GlowToastMessage?

    var hasMore: Bool {
        nextOffset != nil
    }

    var enlargedCard: DeckCard? {
        enlarged.flatMap { id in cards.first { $0.id == id } }
    }

    var confirmingCard: DeckCard? {
        confirming.flatMap { id in cards.first { $0.id == id } }
    }

    @ObservationIgnored private let service: any DeckService
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let refreshInterval: Duration
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "deck")
    @ObservationIgnored private var nextOffset: Int?
    @ObservationIgnored private var pagesLoaded = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    @ObservationIgnored private var firstShownAt: Date?
    @ObservationIgnored private var reportedRecording = false
    @ObservationIgnored private var started = false

    /// - Parameter refreshInterval: the least time between two live refreshes, so a burst of
    ///   `deck.changed` costs one refetch (and stays inside B8's deck rate limit) while still landing
    ///   well within P8's 5 seconds.
    init(
        roomID: RoomID,
        service: any DeckService,
        analytics: any Analytics = NoopAnalytics(),
        refreshInterval: Duration = .milliseconds(1500),
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.roomID = roomID
        self.service = service
        self.analytics = analytics
        self.refreshInterval = refreshInterval
        self.now = now
    }

    // MARK: Starting

    /// Opens What did you notice the first time, and fetches taps left today.
    func start(showMe: Set<Gender>?) async {
        if let showMe, !showMe.isEmpty {
            self.showMe = Gender.allCases.filter(showMe.contains)
        }
        guard !started else { return }
        started = true
        analytics.track(AnalyticsEvent("deck_opened"))
        isNoticeSheetOpen = true
        if let state = try? await service.roomState(roomID) {
            tapsLeftToday = state.tapsLeftToday
            viewsLeftToday = state.viewsLeftToday
            roomSlug = state.slug
        }
    }

    // MARK: What did you notice

    /// Applies what I noticed (or nothing, for everyone) and fetches the first page.
    func apply(_ noticed: NoticedFilters) async {
        filters = noticed.limited(toShowMe: Set(showMe))
        isNoticeSheetOpen = false
        enlarged = nil
        confirming = nil
        analytics.track(AnalyticsEvent("deck_filters_applied", [
            "parts": .int(filters.partsPicked),
            "values": .int(filters.count),
        ]))
        await reload(showingProgress: true)
    }

    // MARK: Loading

    /// Pull to refresh: the same pages again (the order stays the same all day).
    func refresh() async {
        guard phase != .choosing else { return }
        await reload(showingProgress: false)
    }

    /// The next page, when the last card shows.
    func loadMore() async {
        guard let offset = nextOffset, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        loadMoreFailed = false
        let generation = generation
        defer { isLoadingMore = false }
        do {
            let page = try await service.deck(roomID, filters: filters, offset: offset)
            guard generation == self.generation else { return }
            let known = Set(cards.map(\.id))
            cards += page.cards.filter { !known.contains($0.id) }
            nextOffset = page.nextOffset
            viewsLeftToday = page.viewsLeftToday
            pagesLoaded += 1
        } catch {
            guard generation == self.generation else { return }
            loadMoreFailed = error != .cancelled
        }
    }

    /// `deck.changed` arrived: someone here paused, left or blocked. Refetch soon, once per burst.
    func deckChanged() {
        scheduleRefresh()
    }

    /// A card's photo link expired (they last CARD_URL_TTL) or the card left the deck: refetch.
    func imageUnavailable(_ card: CardID) {
        logger.debug("A card photo was unavailable; refreshing")
        _ = card
        scheduleRefresh()
    }

    /// Waits for any scheduled live refresh to finish. For tests.
    func settle() async {
        while let task = refreshTask {
            await task.value
        }
    }

    private func scheduleRefresh() {
        guard phase != .choosing else { return }
        if refreshTask != nil {
            refreshQueued = true
            return
        }
        refreshTask = Task { [weak self] in
            await self?.runScheduledRefresh()
        }
    }

    private func runScheduledRefresh() async {
        if let lastRefresh {
            let wait = refreshInterval - (ContinuousClock.now - lastRefresh)
            if wait > .zero {
                try? await Task.sleep(for: wait)
            }
        }
        await reload(showingProgress: false)
        refreshTask = nil
        if refreshQueued {
            refreshQueued = false
            scheduleRefresh()
        }
    }

    /// Fetches as many pages as are showing, from the start, and replaces the cards.
    private func reload(showingProgress: Bool) async {
        generation += 1
        let generation = generation
        lastRefresh = ContinuousClock.now
        if showingProgress {
            phase = .loading
            cards = []
            nextOffset = nil
            pagesLoaded = 0
        }
        let pagesWanted = max(1, pagesLoaded)
        var collected: [DeckCard] = []
        var offset = 0
        var next: Int?
        var lastPage: DeckPage?
        do {
            for _ in 0 ..< pagesWanted {
                let page = try await service.deck(roomID, filters: filters, offset: offset)
                guard generation == self.generation else { return }
                lastPage = page
                let known = Set(collected.map(\.id))
                collected += page.cards.filter { !known.contains($0.id) }
                next = page.nextOffset
                guard let more = page.nextOffset else { break }
                offset = more
            }
        } catch {
            guard generation == self.generation, error != .cancelled else { return }
            if cards.isEmpty || showingProgress {
                phase = .failed(error)
            } else {
                // Keep what's showing; the next event or pull tries again.
                toast = GlowToastMessage(error == .offline ? DeckCopy.offline : DeckCopy.deckFailed, kind: .error)
            }
            return
        }
        guard let lastPage else { return }
        cards = merged(collected)
        nextOffset = next
        pagesLoaded = cards.isEmpty ? 0 : pagesWanted
        viewsLeftToday = lastPage.viewsLeftToday
        loadMoreFailed = false
        if cards.isEmpty {
            phase = .empty(lastPage.emptyReason ?? .noMatch)
        } else {
            phase = .loaded
            if firstShownAt == nil {
                firstShownAt = now()
            }
        }
        dropGoneSelections()
        analytics.track(AnalyticsEvent("deck_loaded", [
            "cards": .int(cards.count),
            "empty": cards.isEmpty ? Self.literal(lastPage.emptyReason ?? .noMatch) : "none",
        ]))
    }

    /// Keeps a card's current photo link while it's still good, so photos already on screen don't
    /// reload on every live refresh.
    private func merged(_ fresh: [DeckCard]) -> [DeckCard] {
        let current = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stillGood = now().addingTimeInterval(15)
        return fresh.map { card in
            guard let old = current[card.id], old.imageExpiresAt > stillGood else { return card }
            var kept = card
            kept.imageURL = old.imageURL
            kept.imageExpiresAt = old.imageExpiresAt
            return kept
        }
    }

    /// A card that left the deck (they paused, left or blocked) closes if it's open (P8).
    private func dropGoneSelections() {
        let ids = Set(cards.map(\.id))
        var gone = false
        if let enlarged, !ids.contains(enlarged) {
            self.enlarged = nil
            gone = true
        }
        if let confirming, !ids.contains(confirming) {
            self.confirming = nil
            gone = true
        }
        if gone {
            toast = GlowToastMessage(DeckCopy.cardGone)
        }
    }

    // MARK: Cards and tapping

    func open(_ card: CardID) {
        enlarged = card
        analytics.track(AnalyticsEvent("deck_card_opened"))
    }

    func close() {
        confirming = nil
        enlarged = nil
    }

    /// "That's them": asks to confirm.
    func requestTap(_ card: CardID) {
        guard cards.contains(where: { $0.id == card }) else { return }
        confirming = card
    }

    func cancelTap() {
        confirming = nil
    }

    /// Sends the secret tap. Returns the match when it's mutual, for the hand-off to FeatureMatch.
    func confirmTap() async -> MatchID? {
        guard let card = confirming, !isTapping else { return nil }
        isTapping = true
        defer { isTapping = false }
        do {
            let outcome = try await service.tap(card, in: roomID)
            tapsLeftToday = outcome.tapsLeftToday
            if let index = cards.firstIndex(where: { $0.id == card }) {
                cards[index].tappedByMe = true
            }
            confirming = nil
            let seconds = firstShownAt.map { Int(now().timeIntervalSince($0).rounded()) } ?? 0
            switch outcome {
            case .sent:
                analytics.track(AnalyticsEvent("deck_tap", ["result": "sent", "seconds": .int(seconds)]))
                toast = GlowToastMessage(DeckCopy.tapSent, kind: .success)
                return nil
            case let .mutual(match, _):
                analytics.track(AnalyticsEvent("deck_tap", ["result": "mutual", "seconds": .int(seconds)]))
                enlarged = nil
                return match
            }
        } catch {
            switch error {
            case .tapLimitReached:
                tapsLeftToday = 0
                confirming = nil
                toast = GlowToastMessage(DeckCopy.noTapsLeft)
            case .notFound:
                confirming = nil
                enlarged = nil
                toast = GlowToastMessage(DeckCopy.cardGone)
                scheduleRefresh()
            case .rateLimited:
                toast = GlowToastMessage(DeckCopy.slowDown, kind: .error)
            case .offline:
                toast = GlowToastMessage(DeckCopy.offline, kind: .error)
            case .cancelled:
                break
            case .signedOut, .unexpected:
                toast = GlowToastMessage(DeckCopy.tapFailed, kind: .error)
            }
            return nil
        }
    }

    /// The paused empty state's "Be visible".
    func becomeVisible() async -> Bool {
        do {
            let paused = try await service.setPaused(false)
            guard !paused else { return false }
            await reload(showingProgress: true)
            return true
        } catch {
            toast = GlowToastMessage(DeckCopy.pauseFailed, kind: .error)
            return false
        }
    }

    // MARK: Capture (P12)

    /// The screen started being recorded or mirrored while the deck is open. Reported once per
    /// capture, as a recording (B8 can't tell the two apart either, C1-D3).
    func captureChanged(isCaptured: Bool) {
        guard isCaptured else {
            reportedRecording = false
            return
        }
        guard !reportedRecording else { return }
        reportedRecording = true
        enlarged = nil
        confirming = nil
        analytics.track(AnalyticsEvent("deck_capture", ["kind": "recording"]))
        let service = service
        let room = roomID
        Task { await service.reportCapture(.recording, in: room) }
    }

    /// A screenshot was taken while the deck was open: a gentle note, and a report.
    func screenshotTaken() {
        toast = GlowToastMessage(DeckCopy.screenshotNote, duration: .seconds(5))
        analytics.track(AnalyticsEvent("deck_capture", ["kind": "screenshot"]))
        let service = service
        let room = roomID
        Task { await service.reportCapture(.screenshot, in: room) }
    }

    // MARK: Helpers

    private static func literal(_ reason: DeckEmptyReason) -> AnalyticsValue {
        switch reason {
        case .quiet: "quiet"
        case .noMatch: "no_match"
        case .viewLimitReached: "view_limit_reached"
        case .paused: "paused"
        case .checkinEnded: "checkin_ended"
        }
    }

    /// For snapshot tests and previews: puts the model straight into a state.
    func preview(phase: Phase, cards: [DeckCard] = [], filters: NoticedFilters = .none, tapsLeft: Int? = 3, viewsLeft: Int? = 41) {
        self.phase = phase
        self.cards = cards
        self.filters = filters
        tapsLeftToday = tapsLeft
        viewsLeftToday = viewsLeft
        started = true
    }
}
