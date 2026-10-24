import APIClient
import AppCore
import Foundation
import Testing
@testable import FeatureMatch

private let matchID = FixtureMatchClient.revealMatch

/// A location service that's always denied.
private struct DeniedLocation: LocationService {
    func authorization() async -> LocationAuthorization {
        .denied
    }

    func requestAuthorization() async -> LocationAuthorization {
        .denied
    }

    func currentFix(timeout _: Duration) async throws -> LocationFix {
        throw LocationError.denied
    }
}

/// A client that answers every choice with one error, and otherwise behaves like the fixtures.
private struct FailingChoices: MatchClient {
    let base: FixtureMatchClient
    let error: MatchError

    func match(_ id: MatchID) async throws(MatchError) -> MatchSnapshot {
        try await base.match(id)
    }

    func choose(_: MatchSnapshot.Choice, for _: MatchID, fix _: LocationFix?) async throws(MatchError) -> ChoiceOutcome {
        throw error
    }

    func matches() async throws(MatchError) -> [MatchSummary] {
        try await base.matches()
    }

    func events() -> AsyncStream<MatchEvent> {
        base.events()
    }
}

@MainActor
private func makeModel(
    _ client: any MatchClient,
    location: any LocationService = PreviewLocationService(),
) -> MatchModel {
    MatchModel(matchID: matchID, client: client, location: location, analytics: NoopAnalytics())
}

private func choosing(photos: Int = 3, deadline: TimeInterval = GlowConstants.choiceWindow) -> MatchSnapshot {
    var match = FixtureMatchClient.snapshot(matchID, "Blake", status: .choosing, photos: photos)
    match.choiceDeadline = Date.now.addingTimeInterval(deadline)
    return match
}

@MainActor
struct MatchModelTests {
    @Test func loadsTheMatchAndWaitsForAChoice() async {
        let model = makeModel(FixtureMatchClient(matches: [choosing()]))
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .choosing)
        #expect(model.snapshot?.firstName == "Blake")
        #expect(model.route == nil)
    }

    @Test func photosAreNeverAskedForBeforeTheMatchHasLoaded() async {
        // P1: a photo source exists only for a match the server has shown me, and only below
        // photoCount.
        let model = makeModel(FixtureMatchClient(matches: [choosing(photos: 2)]))
        #expect(model.photoSources.isEmpty)

        await model.load()
        #expect(model.photoSources == [.matchPhoto(matchID, index: 0), .matchPhoto(matchID, index: 1)])
    }

    @Test func anEndedMatchHasNoPhotos() async {
        let client = FixtureMatchClient(matches: [choosing(photos: 3)])
        let model = makeModel(client)
        await model.load()
        client.end(matchID)
        await model.handle(MatchEvent(.ended, matchID))
        #expect(model.phase == .gone)
        #expect(model.photoSources.isEmpty)
    }

    @Test func findAndFindOpensTheGlow() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()

        await model.chooseFind()
        #expect(model.phase == .waiting)
        #expect(client.choices.map(\.0) == [.find])

        // They choose Find too: the server starts the glow and sends glow.started.
        client.update(matchID, announce: .glowStarted) { $0.status = .glowing }
        await model.handle(MatchEvent(.glowStarted, matchID))
        #expect(model.route == .glow(matchID))
        #expect(model.phase == .moved(.glow(matchID)))
    }

    @Test func findWhenTheyAlreadyChoseFindOpensTheGlowAtOnce() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        // The server answers both_find: the fixture plays it by having them already glowing.
        client.update(matchID) { $0.status = .glowing }
        await model.chooseFind()
        #expect(model.route == .glow(matchID))
    }

    @Test func findAndChatOpensTheChat() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.chooseFind()
        #expect(model.phase == .waiting)

        client.update(matchID, announce: .choice) { $0.status = .chatting }
        await model.handle(MatchEvent(.choice, matchID))
        #expect(model.route == .chat(matchID))
    }

    @Test func chatOpensTheChatStraightAway() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.chooseChat()
        #expect(model.route == .chat(matchID))
        #expect(client.choices.map(\.0) == [.chat])
    }

    @Test func chatAndChatOpensTheChat() async {
        // They chose Just chat first: opening the match goes straight to the chat.
        var chatting = choosing()
        chatting.status = .chatting
        let model = makeModel(FixtureMatchClient(matches: [chatting]))
        await model.load()
        #expect(model.route == .chat(matchID))
    }

    @Test func waitingCanSwitchToChat() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.chooseFind()
        await model.chooseChat()
        #expect(model.route == .chat(matchID))
        #expect(client.choices.map(\.0) == [.find, .chat])
    }

    @Test func aTimeoutOpensTheChat() async {
        let model = makeModel(FixtureMatchClient(matches: [choosing(deadline: -1)]))
        await model.load()
        #expect(model.route == .chat(matchID))
    }

    @Test func theDeadlineWatcherRefreshesWhenTimeRunsOut() async {
        let model = makeModel(FixtureMatchClient(matches: [choosing(deadline: 0.2)]))
        await model.load()
        #expect(model.phase == .choosing)
        await model.watchDeadline()
        #expect(model.route == .chat(matchID))
    }

    @Test func aRecheckSendsFindAgainWithAFreshFix() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.chooseFind()
        await model.handle(MatchEvent(.recheck, matchID))
        #expect(client.choices.map(\.0) == [.find, .find])
        #expect(model.phase == .waiting)
    }

    @Test func openingAStaleFindSendsItAgainOnce() async {
        // Opened from the match.recheck push: both chose Find, and choosing hasn't ended.
        var stale = choosing()
        stale.yourChoice = .find
        stale.otherHasChosen = true
        let client = FixtureMatchClient(matches: [stale])
        let model = makeModel(client)
        await model.load()
        #expect(client.choices.map(\.0) == [.find])
        await model.load() // a refresh right after doesn't send it again
        #expect(client.choices.count == 1)
    }

    @Test func openingAFindTheyHaventAnsweredSendsNothing() async {
        var waiting = choosing()
        waiting.yourChoice = .find
        let client = FixtureMatchClient(matches: [waiting])
        let model = makeModel(client)
        await model.load()
        #expect(model.phase == .waiting)
        #expect(client.choices.isEmpty)
    }

    @Test func aRecheckIsIgnoredUnlessIChoseFind() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.handle(MatchEvent(.recheck, matchID))
        #expect(client.choices.isEmpty)
    }

    @Test func findWithoutLocationPermissionSendsNothing() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client, location: DeniedLocation())
        await model.load()
        await model.chooseFind()
        #expect(client.choices.isEmpty)
        #expect(model.phase == .choosing)
        #expect(model.notice == .locationDenied)
    }

    @Test func outsideTheRoomShowsANoteAndLetsThemTryAgain() async {
        let base = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(FailingChoices(base: base, error: .notInRoom))
        await model.load()
        await model.chooseFind()
        #expect(model.phase == .choosing)
        #expect(model.notice == .notInRoom)
    }

    @Test func anEndedMatchIsGone() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        client.end(matchID)
        await model.handle(MatchEvent(.ended, matchID))
        #expect(model.phase == .gone)

        let missing = makeModel(FixtureMatchClient(matches: []))
        await missing.load()
        #expect(missing.phase == .gone)
    }

    @Test func eventsForOtherMatchesAreIgnored() async {
        let client = FixtureMatchClient(matches: [choosing()])
        let model = makeModel(client)
        await model.load()
        await model.handle(MatchEvent(.ended, FixtureMatchClient.chattingMatch))
        #expect(model.phase == .choosing)
    }

    @Test func openingAGlowingMatchForwardsToTheGlow() async {
        var glowing = choosing()
        glowing.status = .glowing
        let model = makeModel(FixtureMatchClient(matches: [glowing]))
        await model.load()
        #expect(model.route == .glow(matchID))
    }

    @Test func entryViewsKeepTheMatch() {
        #expect(MutualMomentView(matchID: matchID).matchID == matchID)
        #expect(MatchView(matchID: matchID).matchID == matchID)
    }

    @Test func aFailedLoadCanBeRetried() async {
        let model = makeModel(FixtureMatchClient(matches: [choosing()], failure: .offline))
        await model.load()
        #expect(model.phase == .failed(.offline))
    }
}

@MainActor
struct MatchesListModelTests {
    @Test func splitsNowFromEarlier() async {
        let model = MatchesListModel(client: FixtureMatchClient(.list))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(Set(model.now.map(\.status)) == [.choosing, .glowing])
        #expect(Set(model.earlier.map(\.status)) == [.chatting, .met])
    }

    @Test func rowsOpenTheRightScreen() {
        let now = Date.now
        func row(_ status: MatchSnapshot.Status) -> MatchSummary {
            MatchSummary(id: matchID, status: status, firstName: "Blake", roomName: "Room", createdAt: now, choiceDeadline: now)
        }
        #expect(row(.choosing).route == .match(matchID))
        #expect(row(.glowing).route == .glow(matchID))
        #expect(row(.chatting).route == .chat(matchID))
        #expect(row(.met).route == .chat(matchID))
    }

    @Test func anEndedMatchLeavesTheList() async {
        let client = FixtureMatchClient(.list)
        let model = MatchesListModel(client: client)
        await model.load()
        client.end(FixtureMatchClient.chattingMatch)
        await model.handle(MatchEvent(.ended, FixtureMatchClient.chattingMatch))
        #expect(!model.matches.contains { $0.id == FixtureMatchClient.chattingMatch })
    }
}

struct MatchEventTests {
    @Test func readsMatchEventsFromRealtime() throws {
        let event = try #require(MatchEvent(RealtimeEvent(kind: .matchChoice, matchID: matchID)))
        #expect(event == MatchEvent(.choice, matchID))
        #expect(MatchEvent(RealtimeEvent(kind: .matchCreated, matchID: matchID))?.kind == .created)
    }

    @Test func ignoresRoomEvents() {
        let room = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")
        #expect(MatchEvent(RealtimeEvent(kind: .deckChanged, roomID: room)) == nil)
    }
}
