import AppCore
import Testing
@testable import FeatureDeck

// Placeholder test from A3. Owner: C1.
@MainActor
struct FeatureDeckTests {
    @Test func entryViewsKeepTheRoom() {
        let room = RoomID(rawValue: "00000000-0000-4000-8000-000000000002")
        #expect(RoomHomeView(roomID: room).roomID == room)
        #expect(DeckView(roomID: room).roomID == room)
    }
}
