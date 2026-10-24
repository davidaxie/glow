import AppCore
import Testing
@testable import FeatureRooms

// Placeholder test from A3. Owner: B2.
@MainActor
struct FeatureRoomsTests {
    @Test func joinViewKeepsTheLink() {
        let view = RoomJoinView(link: RoomLink(slug: "demo", token: "ABCD2345"))
        #expect(view.link.slug == "demo")
    }
}
