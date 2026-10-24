import AppCore
import SwiftUI

// Placeholders from A3 so the module graph compiles on day one. Owner: B2.
// Keep these views public with these initializers: the app shows them for `.rooms`, `.scanner`,
// `.roomCode` and `.joinRoom`. Replace everything inside them.

/// The Rooms tab: scan a room's QR code or type its code.
public struct RoomsHomeView: View {
    @Environment(\.navigate) private var navigate

    public init() {}

    public var body: some View {
        PlaceholderScreen("Rooms", module: "FeatureRooms", owner: "B2", details: ["Scan a room's code to join it."]) {
            Button("Scan a code") { navigate(.scanner) }
                .buttonStyle(.borderedProminent)
            Button("Enter a room code") { navigate(.roomCode) }
        }
    }
}

public struct RoomScannerView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Scan", module: "FeatureRooms", owner: "B2")
    }
}

public struct RoomCodeEntryView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Room code", module: "FeatureRooms", owner: "B2")
    }
}

/// Resolves a room link, runs the location check, then sends `.checkIn(roomID, ticket)`.
public struct RoomJoinView: View {
    public let link: RoomLink

    public init(link: RoomLink) {
        self.link = link
    }

    public var body: some View {
        PlaceholderScreen(
            "Join room",
            module: "FeatureRooms",
            owner: "B2",
            details: ["Room: \(link.slug)", link.token == nil ? "No token" : "Token received"],
        )
    }
}

#Preview {
    NavigationStack { RoomJoinView(link: RoomLink(slug: "demo", token: "TOKEN")) }
}
