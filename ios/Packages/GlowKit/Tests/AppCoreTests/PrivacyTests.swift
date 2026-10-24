import Foundation
import Testing
@testable import AppCore

struct PrivacyTests {
    @Test func locationFixNeverPrintsCoordinates() {
        let fix = LocationFix(latitude: 37.802_934, longitude: -122.448_412, accuracy: 12.5, timestamp: .now)
        var dumped = ""
        dump(fix, to: &dumped)
        for text in ["\(fix)", String(describing: fix), String(reflecting: fix), dumped] {
            #expect(!text.contains("37.8"))
            #expect(!text.contains("122.4"))
            #expect(!text.contains("12.5"))
        }
    }

    @Test func roomTokensAndTicketsNeverPrint() {
        let route = Route.joinRoom(RoomLink(slug: "demo", token: "SECRET42"))
        let ticket = JoinTicket("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln")
        var dumped = ""
        dump(route, to: &dumped)
        dump(ticket, to: &dumped)
        for text in ["\(route)", String(reflecting: route), "\(ticket)", dumped] {
            #expect(!text.contains("SECRET42"))
            #expect(!text.contains("eyJ"))
        }
        #expect(route.name == "join_room")
    }

    @Test func scrubberRemovesPersonalData() {
        let text = """
        lat 37.8029345 lng -122.4484123 for robin@example.com with Bearer abc.def-123 \
        at https://glow.example/r/demo?t=SECRET42 token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln
        """
        let scrubbed = PrivacyScrubber.scrub(text)
        for leaked in ["37.8029345", "122.4484123", "robin@example.com", "abc.def-123", "SECRET42", "eyJ"] {
            #expect(!scrubbed.contains(leaked), "leaked \(leaked)")
        }
        #expect(scrubbed.contains("https://glow.example/r/demo?[query]"))
    }

    @Test(arguments: ["lat", "lng", "user_id", "userID", "firstName", "message_text", "photo", "join_ticket"])
    func sensitiveKeysAreDropped(_ key: String) {
        #expect(PrivacyScrubber.isSensitiveKey(key))
    }

    @Test(arguments: ["route", "context", "retries", "taps_left", "via", "screen"])
    func ordinaryKeysAreKept(_ key: String) {
        #expect(!PrivacyScrubber.isSensitiveKey(key))
    }

    @Test func analyticsValuesAreLiteralsOrNumbers() {
        let event = AnalyticsEvent("room_joined", ["via": "qr", "retries": 2, "demo": true])
        #expect(event.name == "room_joined")
        #expect(event.properties["via"] == .literal("qr"))
        #expect(event.properties["retries"] == .int(2))
        #expect(event.properties["demo"] == .bool(true))
    }
}
