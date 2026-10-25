import AppCore
import Foundation
import Observation

/// A card in the local queue, with the moment its signed photo link stops working.
struct BlindDeckEntry: Equatable, Identifiable {
    let card: BlindCard
    let expiresAt: Date

    var id: BlindCardID {
        card.id
    }
}

/// State and rules of the Blind deck, ported from Double Blind's DeckViewModel. A swipe is
/// optimistic: the card leaves at once and the request runs behind it; if it fails, the card comes
/// back. Nothing here learns anything about matches (B2): the only numbers are my own counters.
@MainActor
@Observable
final class BlindDeckModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var entries: [BlindDeckEntry] = []
    private(set) var rightCount = 0
    private(set) var rightRemaining = BlindRulesConstants.dailyRightLimit
    /// A short error under the card. Clears itself.
    private(set) var errorText: String?
    /// Bumped each time a right swipe is tried with none left, so the view can shake the banner.
    private(set) var capNudge = 0
    /// True once a refill found nobody new.
    private(set) var reachedEnd = false
    private(set) var started = false

    @ObservationIgnored private let service: any BlindService
    @ObservationIgnored let images: BlindImageStore
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Swiped this session. Requests may still be in flight, so a refill must not bring them back.
    @ObservationIgnored private var settled: Set<BlindCardID> = []
    @ObservationIgnored private var isRefilling = false
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var lastApplied = 0
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private var inFlight: [Int: Task<Void, Never>] = [:]

    static let lowWater = 4
    static let batch = 10

    init(service: any BlindService, images: BlindImageStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.images = images
        self.now = now
    }

    // MARK: Derived

    var top: BlindDeckEntry? {
        entries.first
    }

    var canSwipeRight: Bool {
        rightRemaining > 0
    }

    var capReached: Bool {
        rightRemaining <= 0
    }

    var dropProgressText: String? {
        BlindDeckRules.dropProgressText(rightCount: rightCount)
    }

    var canOpenDrop: Bool {
        rightCount >= BlindDeckRules.dropMinimum
    }

    // MARK: Loading

    /// First load: counters and the first batch together. Later calls only refresh.
    func start() async {
        guard !started else {
            await refreshOnForeground()
            return
        }
        started = true
        phase = .loading
        await loadPool()
        await refill(force: true)
    }

    func retry() async {
        started = false
        await start()
    }

    /// Back in the foreground or on the tab again: counters may have reset at 00:00 UTC, links may
    /// have expired, and new people may have joined.
    func refreshOnForeground() async {
        guard phase != .loading else { return }
        await loadPool()
        dropStale()
        reachedEnd = false
        await refill(force: entries.count < Self.batch)
    }

    func checkAgain() async {
        reachedEnd = false
        await refill(force: true)
    }

    /// After leaving Blind: forget everything.
    func reset() {
        entries = []
        settled = []
        started = false
        phase = .loading
        rightCount = 0
        rightRemaining = BlindRulesConstants.dailyRightLimit
    }

    func loadPool() async {
        guard let pool = try? await service.pool() else { return }
        rightCount = pool.rightCount
        rightRemaining = pool.rightRemaining
    }

    private func refill(force: Bool) async {
        guard !isRefilling, force || entries.count < Self.lowWater, !reachedEnd || force else { return }
        isRefilling = true
        defer { isRefilling = false }
        do {
            let fetched = try await service.deck(limit: Self.batch)
            let receivedAt = now()
            let known = Set(entries.map(\.id))
            let fresh = fetched.filter { !settled.contains($0.id) && !known.contains($0.id) }
            entries += fresh.map { BlindDeckEntry(card: $0, expiresAt: BlindLink.expiry(of: $0.photo.url, receivedAt: receivedAt)) }
            reachedEnd = fresh.isEmpty
            phase = .ready
            // Links last a minute, so load the whole batch now; a loaded photo no longer needs its link.
            images.preload(entries.map(\.card.photo))
        } catch {
            if entries.isEmpty, phase != .ready {
                phase = .failed(error.message)
            } else {
                showError(error.message)
            }
        }
    }

    /// Drops queued cards whose photo hasn't loaded and whose link is about to expire.
    func dropStale() {
        let current = now()
        entries.removeAll { entry in
            entry.expiresAt.timeIntervalSince(current) < BlindLink.staleMargin && !images.hasImage(entry.card.photo)
        }
    }

    // MARK: Swiping

    /// Removes the top card and sends the swipe. Returns the card that left, or nil when nothing
    /// happened: no card, or a right swipe with none left today (B4), which nudges the cap banner.
    @discardableResult
    func commit(_ kind: BlindSwipeKind) -> BlindDeckEntry? {
        guard let entry = entries.first else { return nil }
        if kind.isRight, !canSwipeRight {
            capNudge += 1
            return nil
        }
        entries.removeFirst()
        settled.insert(entry.id)
        if kind.isRight {
            rightRemaining = max(rightRemaining - 1, 0)
            rightCount += 1
        }
        sequence += 1
        let mine = sequence
        inFlight[mine] = Task { [weak self] in
            await self?.send(entry, kind, sequence: mine)
            self?.inFlight[mine] = nil
        }
        Task { await refill(force: false) }
        return entry
    }

    /// Resolves when every swipe started so far has finished. For tests.
    func waitForPendingSwipes() async {
        for task in Array(inFlight.values) {
            await task.value
        }
    }

    private func send(_ entry: BlindDeckEntry, _ kind: BlindSwipeKind, sequence mine: Int) async {
        do {
            let result = try await service.swipe(entry.id, kind: kind)
            images.evict(entry.card.photo)
            // Answers can arrive out of order; only the newest one may set the counters.
            if mine >= lastApplied {
                lastApplied = mine
                rightCount = result.rightCount
                rightRemaining = result.rightRemaining
            }
        } catch .rightCapReached {
            restore(entry)
            await loadPool()
            rightRemaining = 0
            capNudge += 1
        } catch {
            restore(entry)
            if kind.isRight {
                await loadPool()
            }
            showError(String(localized: "Couldn't save that swipe. It's back on top."))
        }
    }

    private func restore(_ entry: BlindDeckEntry) {
        settled.remove(entry.id)
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.insert(entry, at: 0)
        reachedEnd = false
    }

    private func showError(_ text: String) {
        errorText = text
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.errorText = nil
        }
    }
}
