import AppCore
import SwiftUI

// Placeholders from A3 so the module graph compiles on day one. Owner: B8.
// Keep these views public with these initializers: the app shows them for `.pause`,
// `.deleteAccount`, `.block` and `.report`. Replace everything inside them.

public struct PauseView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Pause", module: "FeatureSafety", owner: "B8")
    }
}

public struct DeleteAccountView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Delete account", module: "FeatureSafety", owner: "B8")
    }
}

/// Shown as a sheet from a card, a match or a chat.
public struct BlockSheet: View {
    public let context: SafetyContext
    @Environment(\.dismiss) private var dismiss

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        NavigationStack {
            PlaceholderScreen("Block", module: "FeatureSafety", owner: "B8") {
                Button("Close") { dismiss() }
            }
        }
    }
}

/// Shown as a sheet from a card, a match or a chat. Reporting also blocks.
public struct ReportSheet: View {
    public let context: SafetyContext
    @Environment(\.dismiss) private var dismiss

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        NavigationStack {
            PlaceholderScreen("Report", module: "FeatureSafety", owner: "B8") {
                Button("Close") { dismiss() }
            }
        }
    }
}

#Preview {
    ReportSheet(context: .chat(MatchID(rawValue: "00000000-0000-4000-8000-000000000001")))
}
