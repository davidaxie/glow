import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Testing
@testable import FeatureSafety

/// Records what the app sends, and answers each operation with a canned status.
final class SafetyServer: Sendable {
    struct Sent: Sendable {
        let operation: String
        let method: HTTPRequest.Method
        let path: String
        let json: [String: String]
    }

    private let log = OSAllocatedUnfairLock(initialState: [Sent]())
    private let answers: [String: MockTransport.Response]

    init(_ answers: [String: MockTransport.Response]) {
        self.answers = answers
    }

    var sent: [Sent] {
        log.withLock { $0 }
    }

    var api: GlowAPI {
        GlowAPI.mock(MockTransport { request, body, _, operation in
            var json: [String: String] = [:]
            if let body {
                let data = try await Data(collecting: body, upTo: 1 << 20)
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    json = object.mapValues { "\($0)" }
                }
            }
            let sent = Sent(operation: operation, method: request.method, path: request.path ?? "", json: json)
            self.log.withLock { $0.append(sent) }
            let answer = self.answers[operation] ?? .status(.notImplemented)
            var fields = HTTPFields()
            if let type = answer.contentType {
                fields[.contentType] = type
            }
            return (HTTPResponse(status: answer.status, headerFields: fields), answer.body.map { HTTPBody($0) })
        })
    }
}

let card = CardID(rawValue: "c0000000-0000-4000-8000-000000000003")
let match = MatchID(rawValue: "a0000000-0000-4000-8000-000000000001")

@MainActor
struct BlockModelTests {
    @Test func blocksFromACardWithOnlyTheCardID() async {
        let server = SafetyServer(["createBlock": .status(.noContent)])
        let analytics = RecordingAnalytics()
        let model = BlockModel(context: .card(card), api: server.api, analytics: analytics)
        await model.block()

        #expect(model.phase == .done)
        #expect(server.sent.count == 1)
        #expect(server.sent.first?.path == "/api/blocks")
        #expect(server.sent.first?.json == ["context": "card", "contextId": card.rawValue])
        #expect(analytics.events == [AnalyticsEvent("safety_blocked", ["from": "card"])])
    }

    @Test func blocksFromAChat() async {
        let server = SafetyServer(["createBlock": .status(.noContent)])
        let model = BlockModel(context: .chat(match), api: server.api, analytics: NoopAnalytics())
        await model.block()
        #expect(model.phase == .done)
        #expect(server.sent.first?.json == ["context": "chat", "contextId": match.rawValue])
        #expect(model.context.matchID == match)
    }

    @Test func aGoneCardSaysSoAndSendsNothingElse() async {
        let server = SafetyServer(["createBlock": .json(#"{"error":{"code":"not_found","message":"Not found."}}"#, status: .notFound)])
        let analytics = RecordingAnalytics()
        let model = BlockModel(context: .card(card), api: server.api, analytics: analytics)
        await model.block()
        #expect(model.phase == .failed(.gone))
        #expect(analytics.events.isEmpty)
    }

    @Test func tooManyTriesAndOffline() async {
        let limited = SafetyServer(["createBlock": .status(.tooManyRequests)])
        let model = BlockModel(context: .card(card), api: limited.api, analytics: NoopAnalytics())
        await model.block()
        #expect(model.phase == .failed(.rateLimited))

        let offline = GlowAPI.mock(MockTransport { _, _, _, _ in throw URLError(.notConnectedToInternet) })
        let offlineModel = BlockModel(context: .card(card), api: offline, analytics: NoopAnalytics())
        await offlineModel.block()
        #expect(offlineModel.phase == .failed(.offline))
    }

    @Test func blocksOnlyOnce() async {
        let server = SafetyServer(["createBlock": .status(.noContent)])
        let model = BlockModel(context: .card(card), api: server.api, analytics: NoopAnalytics())
        await model.block()
        await model.block()
        #expect(server.sent.count == 1)
    }
}

@MainActor
struct ReportModelTests {
    @Test func needsAReason() async {
        let server = SafetyServer(["createReport": .status(.noContent)])
        let model = ReportModel(context: .card(card), api: server.api, analytics: NoopAnalytics())
        #expect(!model.canSubmit)
        await model.submit()
        #expect(server.sent.isEmpty)
        model.reason = .spam
        #expect(model.canSubmit)
    }

    @Test func sendsTheReasonAndTrimmedDetails() async {
        let server = SafetyServer(["createReport": .status(.noContent)])
        let analytics = RecordingAnalytics()
        let model = ReportModel(context: .match(match), api: server.api, analytics: analytics)
        model.reason = .inappropriatePhoto
        model.details = "  kept sending this  \n"
        await model.submit()

        #expect(model.phase == .done)
        #expect(server.sent.first?.path == "/api/reports")
        #expect(server.sent.first?.json == [
            "context": "match",
            "contextId": match.rawValue,
            "reason": "inappropriate_photo",
            "details": "kept sending this",
        ])
        #expect(analytics.events == [AnalyticsEvent("safety_reported", [
            "from": "match", "reason": "inappropriate_photo", "has_details": true,
        ])])
    }

    @Test func leavesOutEmptyDetails() async {
        let server = SafetyServer(["createReport": .status(.noContent)])
        let model = ReportModel(context: .card(card), api: server.api, analytics: NoopAnalytics())
        model.reason = .underage
        model.details = "   "
        await model.submit()
        #expect(server.sent.first?.json["details"] == nil)
        #expect(server.sent.first?.json["reason"] == "underage")
    }

    @Test func capsDetailsAtTheContractLimit() {
        let model = ReportModel(context: .card(card), api: .mock(), analytics: NoopAnalytics())
        model.details = String(repeating: "a", count: GlowConstants.reportDetailsMaxChars + 50)
        #expect(model.details.count == GlowConstants.reportDetailsMaxChars)
    }

    @Test func everyReasonHasAContractValue() {
        let values = Set(ReportReason.allCases.map(\.apiReason.rawValue))
        #expect(values == ["harassment", "inappropriate_photo", "underage", "spam", "unsafe", "other"])
    }
}

@MainActor
struct PauseModelTests {
    @Test func loadsTheCurrentStateAndPauses() async {
        let server = SafetyServer(["setPaused": .json(#"{"paused":true}"#)])
        let session = PreviewSessionService(profile: .preview(paused: false))
        let analytics = RecordingAnalytics()
        let model = PauseModel(api: server.api, session: session, analytics: analytics)
        await model.load()
        #expect(model.paused == false)

        await model.setPaused(true)
        #expect(model.paused == true)
        #expect(model.phase == .ready)
        #expect(server.sent.first?.path == "/api/me/pause")
        #expect(server.sent.first?.json == ["paused": "1"])
        #expect(analytics.events == [AnalyticsEvent("safety_paused", ["paused": true])])
    }

    @Test func sendsNothingWhenNothingChanges() async {
        let server = SafetyServer(["setPaused": .json(#"{"paused":true}"#)])
        let model = PauseModel(api: server.api, session: PreviewSessionService(), analytics: NoopAnalytics(), paused: true)
        await model.setPaused(true)
        #expect(server.sent.isEmpty)
    }

    @Test func keepsTheOldStateWhenItFails() async {
        let server = SafetyServer(["setPaused": .status(.tooManyRequests)])
        let model = PauseModel(api: server.api, session: PreviewSessionService(), analytics: NoopAnalytics(), paused: false)
        await model.setPaused(true)
        #expect(model.paused == false)
        #expect(model.phase == .failed(.rateLimited))
    }
}

@MainActor
struct DeleteAccountModelTests {
    @Test func deletesThenSignsOut() async {
        let server = SafetyServer(["deleteAccount": .status(.noContent)])
        let session = PreviewSessionService(state: .ready)
        let model = DeleteAccountModel(api: server.api, session: session, analytics: NoopAnalytics())
        await model.delete()

        #expect(model.phase == .done)
        #expect(server.sent.first?.method == .delete)
        #expect(server.sent.first?.path == "/api/me")
        #expect(session.current == .signedOut)
        #expect(await session.currentProfile() == nil)
    }

    @Test func staysSignedInWhenItFails() async {
        let server = SafetyServer(["deleteAccount": .status(.serviceUnavailable)])
        let session = PreviewSessionService(state: .ready)
        let model = DeleteAccountModel(api: server.api, session: session, analytics: NoopAnalytics())
        await model.delete()
        #expect(model.phase == .failed(.unexpected))
        #expect(session.current == .ready)
    }
}

@MainActor
struct SheetTests {
    @Test func sheetsKeepTheirContext() {
        let context = SafetyContext.card(card)
        #expect(BlockSheet(context: context).context == context)
        #expect(ReportSheet(context: context).context == context)
    }
}
