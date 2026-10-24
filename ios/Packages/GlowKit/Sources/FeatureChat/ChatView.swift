import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: C4.
// Keep `ChatView(matchID:)` public: the app shows it for `.chat`. Replace everything inside it.

/// The thread with one match.
public struct ChatView: View {
    public let matchID: MatchID
    @Environment(\.navigate) private var navigate

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        PlaceholderScreen("Chat", module: "FeatureChat", owner: "C4")
            .toolbar {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Report") { navigate(.report(.chat(matchID))) }
                    Button("Block", role: .destructive) { navigate(.block(.chat(matchID))) }
                }
            }
    }
}

#Preview {
    NavigationStack { ChatView(matchID: MatchID(rawValue: "00000000-0000-4000-8000-000000000001")) }
}
