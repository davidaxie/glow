import AppCore
import SwiftUI

// Placeholders from A3 so the module graph compiles on day one. Owner: C2.
// Keep these views public with these initializers: the app shows them for `.matches`,
// `.mutual` and `.match`. Replace everything inside them.

/// The Matches tab: active and past matches.
public struct MatchesListView: View {
    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies

    public init() {}

    public var body: some View {
        PlaceholderScreen("Matches", module: "FeatureMatch", owner: "C2", details: ["No matches yet."]) {
            if dependencies.config.environment == .debug {
                Button("Preview the mutual moment") { navigate(.mutual(.placeholder)) }
            }
        }
    }
}

/// The full-screen mutual moment and reveal.
public struct MutualMomentView: View {
    public let matchID: MatchID
    @Environment(\.navigate) private var navigate

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        PlaceholderScreen(
            "Someone you noticed noticed you back.",
            module: "FeatureMatch",
            owner: "C2",
        ) {
            Button("Find each other") { navigate(.glow(matchID)) }
                .buttonStyle(.borderedProminent)
            Button("Just chat") { navigate(.chat(matchID)) }
        }
    }
}

/// One match: photos, first name, and the choice.
public struct MatchView: View {
    public let matchID: MatchID

    public init(matchID: MatchID) {
        self.matchID = matchID
    }

    public var body: some View {
        PlaceholderScreen("Match", module: "FeatureMatch", owner: "C2")
    }
}

extension MatchID {
    /// A made-up match for placeholders and previews.
    static let placeholder = MatchID(rawValue: "00000000-0000-4000-8000-000000000001")
}

#Preview {
    MutualMomentView(matchID: .placeholder)
}
