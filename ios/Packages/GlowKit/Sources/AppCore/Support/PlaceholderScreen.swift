import SwiftUI

/// A stand-in screen for a module whose owner hasn't built it yet. Delete it from your module as
/// soon as your real screen exists.
public struct PlaceholderScreen<Actions: View>: View {
    private let title: String
    private let module: String
    private let owner: String
    private let details: [String]
    private let actions: Actions

    public init(
        _ title: String,
        module: String,
        owner: String,
        details: [String] = [],
        @ViewBuilder actions: () -> Actions = { EmptyView() },
    ) {
        self.title = title
        self.module = module
        self.owner = owner
        self.details = details
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            VStack(spacing: 4) {
                Text("\(module) · \(owner)")
                ForEach(details, id: \.self) { Text($0) }
            }
        } actions: {
            actions
        }
        .accessibilityIdentifier("screen.\(module)")
        .navigationTitle(title)
    }
}

#Preview {
    PlaceholderScreen("Rooms", module: "FeatureRooms", owner: "B2", details: ["Scan a room's code"])
}
