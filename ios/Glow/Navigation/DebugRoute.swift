#if DEBUG
    import AppCore

    /// Debug builds only: the `GlowDebugRoute` launch argument, `<screen>/<matchID>`, as a Route.
    ///
    ///     xcrun simctl launch <udid> com.davidxie.glow -GlowDebugRoute glow/64bfd966-bf7f-426a-b7aa-f0dc371bae1a
    ///
    /// Only the match screens, and only with a valid UUID. Anything else is ignored. Compiled out of
    /// Release, like `GlowDebugOpenURL`.
    enum DebugRoute {
        static func route(for value: String) -> Route? {
            let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let match = MatchID(validating: parts[1]) else { return nil }
            switch parts[0] {
            case "mutual": return .mutual(match)
            case "match": return .match(match)
            case "glow": return .glow(match)
            case "chat": return .chat(match)
            default: return nil
            }
        }
    }
#endif
