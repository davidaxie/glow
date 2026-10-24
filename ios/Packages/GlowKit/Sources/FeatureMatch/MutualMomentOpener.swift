import AppCore
import SwiftUI

extension View {
    /// Opens the mutual moment takeover whenever `match.created` arrives, wherever the person is in
    /// the app. Put it once on the app's root, inside the view that sets `\.navigate`.
    ///
    /// The person who made the second tap also gets there from the deck (C1 navigates to
    /// `.mutual`); if both happen, the Router shows the takeover once.
    public func opensMutualMoments() -> some View {
        modifier(MutualMomentOpener())
    }
}

struct MutualMomentOpener: ViewModifier {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.matchClient) private var clientOverride
    @Environment(\.navigate) private var navigate

    func body(content: Content) -> some View {
        content.task {
            let client = MatchClients.resolve(clientOverride, dependencies)
            for await event in dependencies.matchEvents(client) where event.kind == .created {
                dependencies.analytics.track(AnalyticsEvent("match_takeover_opened", ["via": "realtime"]))
                navigate(.mutual(event.matchID))
            }
        }
    }
}
