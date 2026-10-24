import AppCore
import Testing
@testable import FeatureCheckIn

// Placeholder test from A3. Owner: B3.
@MainActor
struct FeatureCheckInTests {
    @Test func entryViewKeepsTheRoom() {
        let room = RoomID(rawValue: "00000000-0000-4000-8000-000000000002")
        #expect(CheckInView(roomID: room, ticket: JoinTicket("t")).roomID == room)
    }
}
