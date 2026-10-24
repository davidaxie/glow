import AppCore
import Testing
@testable import Glow

/// The Debug-only `GlowDebugRoute` launch argument opens match screens and nothing else.
struct DebugRouteTests {
    let match = MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a")

    @Test func opensTheMatchScreens() {
        #expect(DebugRoute.route(for: "glow/64bfd966-bf7f-426a-b7aa-f0dc371bae1a") == .glow(match))
        #expect(DebugRoute.route(for: "mutual/64bfd966-bf7f-426a-b7aa-f0dc371bae1a") == .mutual(match))
        #expect(DebugRoute.route(for: "match/64bfd966-bf7f-426a-b7aa-f0dc371bae1a") == .match(match))
        #expect(DebugRoute.route(for: "chat/64BFD966-BF7F-426A-B7AA-F0DC371BAE1A") == .chat(match))
    }

    @Test(arguments: ["", "glow", "glow/", "glow/not-a-uuid", "settings/64bfd966-bf7f-426a-b7aa-f0dc371bae1a", "rooms"])
    func ignoresAnythingElse(_ value: String) {
        #expect(DebugRoute.route(for: value) == nil)
    }
}
