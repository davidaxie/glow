import AppCore
import LiveActivityShared
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: C3.
// Keep `GlowView(matchID:)` public: the app shows it full screen for `.glow`. Replace everything
// inside it.

/// The full-screen glow: color, code word, meeting spot and the 15-minute countdown.
public struct GlowView: View {
    public let matchID: MatchID
    @Environment(\.navigate) private var navigate

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        PlaceholderScreen("Glow", module: "FeatureGlow", owner: "C3") {
            Button("Switch to chat") { navigate(.chat(matchID)) }
        }
    }
}

#Preview {
    GlowView(matchID: MatchID(rawValue: "00000000-0000-4000-8000-000000000001"))
}
