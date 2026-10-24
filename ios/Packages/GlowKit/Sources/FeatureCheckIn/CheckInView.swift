import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B3.
// Keep `CheckInView(roomID:ticket:)` public: the app shows it for `.checkIn`. Replace everything
// inside it.

/// Outfit photo, blur preview and tags, then upload with the join ticket.
public struct CheckInView: View {
    public let roomID: RoomID
    public let ticket: JoinTicket

    public init(roomID: RoomID, ticket: JoinTicket) {
        self.roomID = roomID
        self.ticket = ticket
    }

    public var body: some View {
        PlaceholderScreen("Check in", module: "FeatureCheckIn", owner: "B3")
    }
}

#Preview {
    NavigationStack {
        CheckInView(roomID: RoomID(rawValue: "00000000-0000-4000-8000-000000000001"), ticket: JoinTicket("preview"))
    }
}
