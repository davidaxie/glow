import SwiftUI

/// Sends a Route to the app's Router. Read it from the environment:
///
/// ```swift
/// @Environment(\.navigate) private var navigate
/// Button("Just chat") { navigate(.chat(matchID)) }
/// ```
///
/// In previews and tests it does nothing unless you set one, so you can record what a view sends:
///
/// ```swift
/// .environment(\.navigate, NavigateAction { sent.append($0) })
/// ```
public struct NavigateAction: Sendable {
    private let handler: @MainActor @Sendable (Route) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (Route) -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction(_ route: Route) {
        handler(route)
    }
}

extension EnvironmentValues {
    /// Opens a Route. Set by the app's root view.
    @Entry public var navigate = NavigateAction { _ in }
}
