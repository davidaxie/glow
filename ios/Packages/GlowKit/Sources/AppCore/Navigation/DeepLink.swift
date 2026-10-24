import Foundation

/// Turns an incoming URL into a Route.
///
/// Accepted:
/// - `https://{DOMAIN}/r/{slug}?t={token}`, the universal link in every room QR code.
/// - `glow://r/{slug}?t={token}`, only when `AppConfig.allowsCustomScheme` (Debug builds).
///
/// Anything else is ignored. A malformed token is dropped rather than passed on, so the person can
/// still type the room code.
public enum DeepLink {
    public static func route(for url: URL, config: AppConfig) -> Route? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }

        let segments: [String]
        switch scheme {
        case "https":
            guard components.host?.lowercased() == config.webDomain, components.port == nil else { return nil }
            segments = components.path.split(separator: "/").map(String.init)
        case AppConfig.customScheme:
            guard config.allowsCustomScheme, let host = components.host else { return nil }
            segments = [host] + components.path.split(separator: "/").map(String.init)
        default:
            return nil
        }

        guard segments.count == 2, segments[0].lowercased() == "r" else { return nil }
        let slug = segments[1].lowercased()
        guard RoomLink.isValidSlug(slug) else { return nil }

        let token = components.queryItems?.first(where: { $0.name == "t" })?.value
        let validToken = token.flatMap { RoomLink.isValidToken($0) ? $0 : nil }
        return .joinRoom(RoomLink(slug: slug, token: validToken))
    }
}
