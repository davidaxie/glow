import AppCore
import SwiftUI

// Placeholders from A3 so the module graph compiles on day one. Owner: C1.
// Keep these views public with these initializers: the app shows them for `.roomHome` and
// `.deck`. Replace everything inside them.

/// The room's home: name, check-in status and time left, Visible or Paused, Leave.
public struct RoomHomeView: View {
    public let roomID: RoomID
    @Environment(\.navigate) private var navigate

    public init(roomID: RoomID) {
        self.roomID = roomID
    }

    public var body: some View {
        PlaceholderScreen("Room", module: "FeatureDeck", owner: "C1") {
            Button("See today's looks") { navigate(.deck(roomID)) }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Today's-look cards.
public struct DeckView: View {
    public let roomID: RoomID

    public init(roomID: RoomID) {
        self.roomID = roomID
    }

    public var body: some View {
        PlaceholderScreen("Deck", module: "FeatureDeck", owner: "C1")
    }
}

#Preview {
    NavigationStack { RoomHomeView(roomID: RoomID(rawValue: "00000000-0000-4000-8000-000000000001")) }
}
