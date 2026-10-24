import APIClient
import AppCore
import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureDeck

/// Every screen state of FeatureDeck, at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/DeckSnapshotTests` and
/// run `scripts/sim.sh test FeatureDeck` twice (the first run records and fails).
/// The default text size and the largest accessibility size.
let deckSnapshotSizes: [DynamicTypeSize] = [.large, .accessibility5]

@MainActor
@Suite(.serialized)
struct DeckSnapshotTests {
    // MARK: Deck

    @Test(arguments: deckSnapshotSizes)
    func choosing(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(now: { testNow }))
        model.preview(phase: .choosing)
        await snapshot(deck(model), "choosing", size)
    }

    @Test(arguments: deckSnapshotSizes)
    func loading(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(now: { testNow }))
        model.preview(phase: .loading)
        await snapshot(deck(model), "loading", size)
    }

    @Test(arguments: deckSnapshotSizes)
    func grid(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.start(showMe: nil, viewerCode: "YTVFCREQ")
        await model.apply(.none)
        await snapshot(deck(model), "grid", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func gridFilteredWithATap(_ size: DynamicTypeSize) async throws {
        let model = makeModel(FixtureDeckService(count: 200, now: { testNow }))
        await model.start(showMe: nil, viewerCode: "YTVFCREQ")
        var noticed = NoticedFilters()
        noticed.topColors = [.green]
        noticed.hairLengths = [.short]
        await model.apply(noticed)
        let card = try #require(model.cards.first { $0.id != FixtureDeckService.mutualCard })
        model.requestTap(card.id)
        _ = await model.confirmTap()
        model.toast = nil
        await snapshot(deck(model), "grid-filtered-tapped", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func enlarged(_ size: DynamicTypeSize) async throws {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.start(showMe: nil, viewerCode: "YTVFCREQ")
        await model.apply(.none)
        try model.open(#require(model.cards.dropFirst().first?.id))
        await snapshot(deck(model), "enlarged", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func confirmTap(_ size: DynamicTypeSize) async throws {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.start(showMe: nil, viewerCode: "YTVFCREQ")
        await model.apply(.none)
        let card = try #require(model.cards.dropFirst().first?.id)
        model.open(card)
        model.requestTap(card)
        await snapshot(deck(model), "confirm", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func noTapsLeft(_ size: DynamicTypeSize) async throws {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.apply(.none)
        let card = try #require(model.cards.dropFirst().first)
        model.preview(phase: .loaded, cards: model.cards, tapsLeft: 0, viewsLeft: 40)
        model.open(card.id)
        await snapshot(deck(model), "no-taps-left", size, wait: 0.6)
    }

    @Test(arguments: [
        (FixtureDeckService.Scenario.quiet, "empty-quiet"),
        (.checkinEnded, "empty-checkin-ended"),
        (.paused, "empty-paused"),
        (.viewLimitReached, "empty-view-limit"),
    ], deckSnapshotSizes)
    func empty(_ scenario: (FixtureDeckService.Scenario, String), _ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(scenario: scenario.0, now: { testNow }))
        await model.apply(.none)
        await snapshot(deck(model), scenario.1, size)
    }

    @Test(arguments: deckSnapshotSizes)
    func emptyNoMatch(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(count: 4, now: { testNow }))
        var noticed = NoticedFilters()
        noticed.extras = Set(CardExtra.allCases)
        await model.apply(noticed)
        await snapshot(deck(model), "empty-no-match", size)
    }

    @Test(arguments: deckSnapshotSizes)
    func failed(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(now: { testNow }))
        model.preview(phase: .failed(.offline))
        await snapshot(deck(model), "failed-offline", size)
    }

    /// P12: while the screen is recorded or mirrored, the deck isn't drawn at all.
    @Test(arguments: deckSnapshotSizes)
    func hiddenWhileRecorded(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.apply(.none)
        await snapshot(deck(model).environment(\.isSceneCaptured, true), "hidden-recording", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func screenshotNote(_ size: DynamicTypeSize) async {
        let model = makeModel(FixtureDeckService(count: 24, now: { testNow }))
        await model.apply(.none)
        model.screenshotTaken()
        await snapshot(deck(model), "screenshot-note", size, wait: 0.6)
    }

    @Test(arguments: deckSnapshotSizes)
    func whatDidYouNotice(_ size: DynamicTypeSize) async {
        var noticed = NoticedFilters()
        noticed.genders = [.woman]
        noticed.topColors = [.green]
        noticed.extras = [.glasses]
        let sheet = NoticeSheet(showMe: [.woman, .man], initial: noticed) { _ in }
        await snapshot(sheet, "what-did-you-notice", size)
    }

    // MARK: Room home

    @Test(arguments: [
        (RoomStateCase.checkedIn, "room-checked-in"),
        (.paused, "room-paused"),
        (.checkinEnded, "room-checkin-ended"),
        (.cardRemoved, "room-card-removed"),
        (.roomEnded, "room-ended"),
        (.failed, "room-failed"),
        (.loading, "room-loading"),
    ], deckSnapshotSizes)
    func roomHome(_ state: (RoomStateCase, String), _ size: DynamicTypeSize) async {
        let model = RoomHomeModel(roomID: testRoom, service: FixtureDeckService(now: { testNow }))
        model.preview(state.0.phase, paused: state.0 == .paused)
        let view = NavigationStack { RoomHomeScreen(model: model) }
        await snapshot(view, state.1, size)
    }

    // MARK: Helpers

    enum RoomStateCase: Sendable, Equatable {
        case checkedIn, paused, checkinEnded, cardRemoved, roomEnded, failed, loading

        var phase: RoomHomeModel.Phase {
            let now = testNow
            func snapshot(status: Components.Schemas.RoomStatus = .live, checkin: RoomSnapshot.Checkin?) -> RoomHomeModel.Phase {
                .loaded(RoomSnapshot(
                    name: "Glow demo room (test data)",
                    slug: "demo",
                    status: status,
                    endsAt: now.addingTimeInterval(6 * 3600),
                    checkin: checkin,
                    tapsLeftToday: 2,
                    viewsLeftToday: 37,
                ))
            }
            let open = RoomSnapshot.Checkin(
                joinedAt: now.addingTimeInterval(-600),
                expiresAt: now.addingTimeInterval(2 * 3600 + 41 * 60 + 30),
                visible: true,
            )
            switch self {
            case .checkedIn, .paused: return snapshot(checkin: open)
            case .checkinEnded: return snapshot(checkin: nil)
            case .cardRemoved: return snapshot(checkin: .init(joinedAt: open.joinedAt, expiresAt: open.expiresAt, visible: false))
            case .roomEnded: return snapshot(status: .ended, checkin: nil)
            case .failed: return .failed(.offline)
            case .loading: return .loading
            }
        }
    }

    private func makeModel(_ service: FixtureDeckService) -> DeckModel {
        DeckModel(roomID: testRoom, service: service, refreshInterval: .zero, now: { testNow })
    }

    private func deck(_ model: DeckModel) -> some View {
        NavigationStack { DeckScreen(model: model, checkInAgain: .scanner) }
    }

    /// Hosts the view in a window for `wait` seconds, so its photos load (asynchronously, like the
    /// real loader), then snapshots it. (SnapshotTesting's `.wait` strategy hangs under Swift Testing.)
    private func snapshot(
        _ view: some View,
        _ name: String,
        _ size: DynamicTypeSize,
        wait: TimeInterval = 0.2,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName _: String = #function,
        line: UInt = #line,
        column: UInt = #column,
    ) async {
        let host = view
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)
            .environment(\.deckHidesWhenInactive, false)
            .environment(\.deckClock) { testNow }
            .environment(\.dependencies, .preview(imaging: FixtureImagingService()))
        let traits = UITraitCollection { traits in
            traits.displayScale = 1
            traits.userInterfaceStyle = .dark
            traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
        }
        let controller = UIHostingController(rootView: host)
        controller.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .seconds(wait))
        assertSnapshot(
            of: controller,
            as: .image(on: .iPhone13, precision: 0.99, perceptualPrecision: 0.98, traits: traits),
            named: "\(name)-\(size == .large ? "default" : "ax5")",
            fileID: fileID,
            file: filePath,
            testName: "deck",
            line: line,
            column: column,
        )
    }
}
