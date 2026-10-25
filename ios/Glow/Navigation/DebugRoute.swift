#if DEBUG
    import AppCore

    /// Debug builds only: the `GlowDebugRoute` launch argument, `<screen>/<id>`, as a Route.
    ///
    ///     xcrun simctl launch <udid> com.davidxie.glow -GlowDebugRoute glow/64bfd966-bf7f-426a-b7aa-f0dc371bae1a
    ///
    /// The match screens (`mutual`, `match`, `glow`, `chat` with a match ID) and a room's screens
    /// (`room`, `deck` with a room ID, C1), and only with a valid UUID. Anything else is ignored.
    /// Compiled out of Release, like `GlowDebugOpenURL`.
    enum DebugRoute {
        private static let roomScreens: [String: @Sendable (RoomID) -> Route] = ["room": Route.roomHome, "deck": Route.deck]
        private static let matchScreens: [String: @Sendable (MatchID) -> Route] = [
            "mutual": Route.mutual, "match": Route.match, "glow": Route.glow, "chat": Route.chat,
        ]

        static func route(for value: String) -> Route? {
            let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            if let screen = roomScreens[parts[0]] {
                return RoomID(validating: parts[1]).map(screen)
            }
            if let screen = matchScreens[parts[0]] {
                return MatchID(validating: parts[1]).map(screen)
            }
            return nil
        }
    }
#endif
