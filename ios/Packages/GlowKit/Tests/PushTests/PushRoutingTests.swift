import AppCore
import Foundation
import Testing
@testable import Push

/// A tapped notification opens the screen for its event. Driven by the same `.apns` fixtures
/// `scripts/sim.sh push` sends, which a server test keeps identical to the real payloads.
struct PushRoutingTests {
    static let match = MatchID(rawValue: "f1c70000-0000-4000-8000-000000000001")
    static let room = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")

    static let expected: [String: Route] = [
        "match_created": .mutual(match),
        "match_choice": .match(match),
        "match_recheck": .match(match),
        "match_ended": .matches,
        "glow_started": .glow(match),
        "glow_ended": .chat(match),
        "message_created": .chat(match),
        "checkin_expiring": .roomHome(room),
        "deck_changed": .deck(room),
    ]

    @Test(arguments: expected.keys.sorted())
    func fixtureOpensTheRightScreen(fixture: String) throws {
        let notification = try PushFixtures.notification(fixture)
        #expect(PushRouting.route(for: notification) == Self.expected[fixture])
        #expect(PreviewPushService().route(for: notification) == Self.expected[fixture])
    }

    @Test func thereIsAFixtureForEveryEvent() throws {
        let names = try PushFixtures.names()
        #expect(names == Self.expected.keys.sorted())
        let eventNames = RealtimeEventKind.allCases.map { $0.rawValue.replacingOccurrences(of: ".", with: "_") }
        #expect(Set(eventNames) == Set(names))
    }

    @Test func ignoresKeysThatArentTheEvent() {
        let payload = #"{"aps":{"alert":{"body":"x"}},"type":"message.created","#
            + #""matchId":"F1C70000-0000-4000-8000-000000000001","senderName":"Robin"}"#
        let event = PushNotification(categoryIdentifier: "MESSAGE", payload: Data(payload.utf8)).event
        #expect(event == RealtimeEvent(kind: .messageCreated, matchID: Self.match))
    }

    @Test(arguments: [
        #"{}"#,
        #"not json"#,
        #"{"type":"match.created"}"#,
        #"{"type":"match.created","matchId":"not-a-uuid"}"#,
        #"{"type":"match.created","roomId":"de000000-0000-4000-8000-000000000001"}"#,
        #"{"type":"match.secret","matchId":"f1c70000-0000-4000-8000-000000000001"}"#,
        #"{"type":"deck.changed","matchId":"f1c70000-0000-4000-8000-000000000001"}"#,
        #"{"type":7,"matchId":"f1c70000-0000-4000-8000-000000000001"}"#,
    ])
    func refusesAnythingElse(payload: String) {
        let notification = PushNotification(categoryIdentifier: "MATCH", payload: Data(payload.utf8))
        #expect(notification.event == nil)
        #expect(PushRouting.route(for: notification) == nil)
    }
}

/// Reads `ios/fixtures/push/*.apns` from the repo. Simulator tests can read the Mac's files.
enum PushFixtures {
    static var directory: URL {
        URL(filePath: #filePath) // ios/Packages/GlowKit/Tests/PushTests/PushRoutingTests.swift
            .deletingLastPathComponent() // …/Tests/PushTests
            .deletingLastPathComponent() // …/GlowKit/Tests
            .deletingLastPathComponent() // …/Packages/GlowKit
            .deletingLastPathComponent() // ios/Packages
            .deletingLastPathComponent() // ios
            .appending(path: "fixtures/push")
    }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".apns") }
            .map { String($0.dropLast(".apns".count)) }
            .sorted()
    }

    static func json(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appending(path: "\(name).apns"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// What the app delegate hands the Push service: the userInfo as JSON, and the category.
    static func notification(_ name: String) throws -> PushNotification {
        var userInfo = try json(name)
        userInfo.removeValue(forKey: "Simulator Target Bundle")
        let category = ((userInfo["aps"] as? [String: Any])?["category"] as? String) ?? ""
        let data = try JSONSerialization.data(withJSONObject: userInfo, options: [.sortedKeys])
        return PushNotification(categoryIdentifier: category, payload: data)
    }
}
