import AppCore
import DesignSystem
import Foundation
import Testing
@testable import FeatureChat

// Owner: C4. The chat model: loading, sending (instant, sent, failed, retried), live updates,
// review removals, the thread ending, and unmatch.

@MainActor
struct ChatModelTests {
    let match = PreviewChatAPI.sampleMatch

    func makeModel(_ api: PreviewChatAPI, analytics: RecordingAnalytics = RecordingAnalytics()) -> ChatModel {
        ChatModel(matchID: match, api: api, analytics: analytics, now: { PreviewChatAPI.sampleNow })
    }

    @Test func entryViewKeepsTheMatch() {
        #expect(ChatView(matchID: match).matchID == match)
    }

    @Test func loadsTheThreadOldestFirstWithTheirName() async {
        let model = makeModel(PreviewChatAPI())
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.header?.firstName == "Sam")
        #expect(model.items.map(\.body) == PreviewChatAPI.sampleThread.map(\.body))
        #expect(!model.hasOlder)
    }

    @Test func sendingShowsAtOnceThenSent() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        model.draft = "  On my way \n"
        #expect(model.outgoingBody == "On my way")
        api.delaySends(by: .milliseconds(300))
        let sending = Task { await model.send() }
        for _ in 0 ..< 50 where model.outgoing.isEmpty {
            await Task.yield()
        }
        // The draft clears and the message shows as sending before the server answers.
        #expect(model.draft.isEmpty)
        #expect(model.outgoing.map(\.delivery) == [.sending])
        #expect(model.rows.last?.message.body == "On my way")
        await sending.value
        #expect(model.outgoing.isEmpty)
        let last = model.items.last
        #expect(last?.body == "On my way")
        #expect(last?.fromMe == true)
        #expect(last?.delivery == .sent)
        #expect(api.sentBodies == ["On my way"])
        #expect(model.rows.last?.showsSent == true)
    }

    @Test func aFailedSendCanBeRetriedWithTheSameClientID() async throws {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.offline)
        model.draft = "Are you near the stage?"
        await model.send()
        let failed = try #require(model.outgoing.first)
        #expect(failed.delivery == .failed(.network))
        #expect(api.messageCount == PreviewChatAPI.sampleThread.count)

        await model.retry(failed.id)
        #expect(model.outgoing.isEmpty)
        #expect(model.items.filter { $0.body == "Are you near the stage?" }.count == 1)
        let clientID = try #require(failed.clientID)
        #expect(api.sentClientIDs == [clientID])
    }

    @Test func aRejectedMessageCanBeEditedButNotRetried() async throws {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.rejected)
        model.draft = "something moderation refuses"
        await model.send()
        let failed = try #require(model.outgoing.first)
        #expect(failed.delivery == .failed(.rejected))

        await model.retry(failed.id)
        #expect(api.sentBodies.isEmpty)

        model.edit(failed.id)
        #expect(model.outgoing.isEmpty)
        #expect(model.draft == "something moderation refuses")
    }

    @Test func rateLimitedAndDiscarded() async throws {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.rateLimited)
        model.draft = "one more"
        await model.send()
        let failed = try #require(model.outgoing.first)
        #expect(failed.delivery == .failed(.rateLimited))
        model.discard(failed.id)
        #expect(model.outgoing.isEmpty)
    }

    @Test func theComposerCountsLikeTheServer() async {
        let model = makeModel(PreviewChatAPI())
        await model.start()
        #expect(!model.canSend)
        model.draft = " \n "
        #expect(!model.canSend)
        model.draft = String(repeating: "a", count: ChatModel.maxLength)
        #expect(model.canSend)
        #expect(model.remaining == 0)
        // An emoji is two UTF-16 code units, which is what the server's limit counts.
        model.draft = String(repeating: "a", count: ChatModel.maxLength - 1) + "🙂"
        #expect(model.remaining == -1)
        #expect(!model.canSend)
    }

    @Test func aNewMessageEventForThisMatchRefreshes() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        let realtime = PreviewRealtimeService()
        let listening = Task { await model.listen(to: realtime.events()) }
        await Task.yield()

        api.receive("I'm by the left speaker")
        realtime.emit(RealtimeEvent(kind: .messageCreated, matchID: MatchID(rawValue: "11111111-0000-4000-8000-000000000000")))
        realtime.emit(RealtimeEvent(kind: .messageCreated, matchID: match))
        for _ in 0 ..< 50 where model.items.last?.body != "I'm by the left speaker" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.items.last?.body == "I'm by the left speaker")
        #expect(model.items.last?.fromMe == false)
        // The other match's event didn't cost a request: one load, one refresh.
        #expect(api.pageRequests.count == 2)
        listening.cancel()
    }

    @Test func aMessageTheReviewRemovedDisappears() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        let removed = PreviewChatAPI.sampleThread[2]
        api.remove(removed.id)
        await model.refresh()
        #expect(!model.items.contains { $0.id == removed.id })
    }

    @Test func whenTheMatchEndsTheThreadIsClearedAndSendingStops() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failPages(.ended)
        let realtime = PreviewRealtimeService()
        let listening = Task { await model.listen(to: realtime.events()) }
        await Task.yield()
        realtime.emit(RealtimeEvent(kind: .messageCreated, matchID: match))
        for _ in 0 ..< 50 where model.phase != .ended {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.phase == .ended)
        #expect(model.items.isEmpty)
        model.draft = "hello?"
        #expect(!model.canSend)
        await model.send()
        #expect(api.sentBodies.isEmpty)
        listening.cancel()
    }

    @Test func aSendThatFindsTheMatchGoneEndsTheChat() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.ended)
        model.draft = "still there?"
        await model.send()
        #expect(model.phase == .ended)
        #expect(model.items.isEmpty)
    }

    @Test func notOpenYet() async {
        let api = PreviewChatAPI()
        api.failPages(.notOpen)
        let model = makeModel(api)
        await model.start()
        #expect(model.phase == .notOpen)
    }

    @Test func aFirstLoadThatFailsCanBeRetried() async {
        let api = PreviewChatAPI()
        api.failPages(.offline)
        let model = makeModel(api)
        await model.start()
        #expect(model.phase == .failed)
        api.failPages(nil)
        await model.refresh()
        #expect(model.phase == .ready)
        #expect(model.items.count == PreviewChatAPI.sampleThread.count)
    }

    @Test func pagesBackToTheStart() async {
        let thread = (0 ..< 7).map { PreviewChatAPI.sample($0, "m\($0)", fromMe: $0.isMultiple(of: 2), minutesAgo: Double(70 - $0)) }
        let api = PreviewChatAPI(thread: thread, pageSize: 3)
        let model = makeModel(api)
        await model.start()
        #expect(model.items.map(\.body) == ["m4", "m5", "m6"])
        #expect(model.hasOlder)
        await model.loadOlder()
        await model.loadOlder()
        #expect(model.items.map(\.body) == thread.map(\.body))
        #expect(!model.hasOlder)
        // A refresh keeps the older pages and replaces only the newest one.
        api.receive("m7")
        await model.refresh()
        #expect(model.items.map(\.body) == thread.map(\.body) + ["m7"])
    }

    @Test func unmatchEndsTheChat() async {
        let api = PreviewChatAPI()
        let analytics = RecordingAnalytics()
        let model = makeModel(api, analytics: analytics)
        await model.start()
        #expect(await model.unmatch())
        #expect(model.phase == .ended)
        #expect(model.items.isEmpty)
        #expect(api.unmatchCount == 1)
        #expect(analytics.names.contains("chat_unmatched"))
    }

    @Test func unmatchingAnAlreadyEndedMatchStillCloses() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.ended)
        #expect(await model.unmatch())
        #expect(model.phase == .ended)
    }

    @Test func aFailedUnmatchSaysSoAndKeepsTheThread() async {
        let api = PreviewChatAPI()
        let model = makeModel(api)
        await model.start()
        api.failNextSends(.offline)
        #expect(await model.unmatch() == false)
        #expect(model.notice == .unmatchFailed)
        #expect(model.phase == .ready)
        #expect(!model.items.isEmpty)
    }

    @Test func analyticsNeverCarryMessageText() async {
        let api = PreviewChatAPI()
        let analytics = RecordingAnalytics()
        let model = makeModel(api, analytics: analytics)
        await model.start()
        model.draft = "meet me at the bar"
        await model.send()
        api.failNextSends(.rejected)
        model.draft = "a secret"
        await model.send()
        let everything = analytics.events.map { "\($0.name) \($0.properties)" }.joined(separator: "\n")
        #expect(analytics.names == ["chat_opened", "chat_message_sent", "chat_message_failed"])
        #expect(!everything.contains("bar"))
        #expect(!everything.contains("secret"))
    }
}

struct ChatLayoutTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    @Test func timesShowAfterAPause() {
        let rows = ChatLayout.rows(for: PreviewChatAPI.sampleThread, now: PreviewChatAPI.sampleNow, calendar: calendar)
        #expect(rows.map { $0.timeLabel != nil } == [true, false, false, true, false])
        #expect(rows[0].timeLabel == "7:48\u{202F}PM")
        // Only my newest message says Sent, and only when it's the last one.
        #expect(rows.allSatisfy { !$0.showsSent })
    }

    @Test func yesterdayAndOlder() {
        let now = PreviewChatAPI.sampleNow
        #expect(ChatLayout.label(for: now.addingTimeInterval(-86400), now: now, calendar: calendar) == "Yesterday 8:30\u{202F}PM")
        #expect(ChatLayout.label(for: now.addingTimeInterval(-3 * 86400), now: now, calendar: calendar).hasPrefix("Oct"))
    }

    @Test func sentShowsUnderMyLastMessage() {
        var thread = PreviewChatAPI.sampleThread
        thread.append(PreviewChatAPI.sample(6, "On my way", fromMe: true, minutesAgo: 1))
        let rows = ChatLayout.rows(for: thread, now: PreviewChatAPI.sampleNow, calendar: calendar)
        #expect(rows.map(\.showsSent) == [false, false, false, false, false, true])
    }
}

struct ChatBubbleContrastTests {
    @Test func aSendingBubbleStillMeetsAA() {
        let fade = 1 - ChatBubble.sendingOpacity
        let fill = GlowPalette.accent.mixed(with: GlowPalette.background, amount: fade)
        let text = GlowPalette.onAccent.mixed(with: GlowPalette.background, amount: fade)
        #expect(GlowContrast.ratio(text, fill) >= GlowContrast.minimumTextRatio)
    }
}

struct LiveChatAPIWireTests {
    @Test func nextBeforeGoesBackToTheExactMillisecond() throws {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        for ms in 0 ..< 1000 {
            let wire = String(format: "2026-10-24T20:15:07.%03dZ", ms)
            let parsed = try style.parse(wire)
            #expect(LiveChatAPI.wireDate(parsed).formatted(style) == wire)
        }
    }
}

/// Keeps every event, for checking what the chat reports.
final class RecordingAnalytics: Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AnalyticsEvent] = []

    var events: [AnalyticsEvent] {
        lock.withLock { recorded }
    }

    var names: [String] {
        events.map(\.name)
    }

    func track(_ event: AnalyticsEvent) {
        lock.withLock { recorded.append(event) }
    }

    func record(_: any Error, context _: StaticString) {}
}
