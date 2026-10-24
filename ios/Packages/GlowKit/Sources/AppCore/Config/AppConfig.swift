import Foundation

/// Build configuration, read once at launch from the app's Info.plist (which gets it from
/// `ios/Glow/Config/*.xcconfig`).
///
/// The app only ever holds the API URL, the Supabase URL and the Supabase anon key, plus the
/// public PostHog and Sentry client keys. No secrets (AGENTS.md: Secrets).
public struct AppConfig: Sendable, Hashable {
    public enum Environment: String, Sendable, Hashable {
        case debug
        case release
    }

    public var environment: Environment
    /// `API_BASE_URL`: `http://localhost:3000` in Debug, `https://{DOMAIN}` in Release.
    public var apiBaseURL: URL
    /// `SUPABASE_URL`. Nil when not configured yet.
    public var supabaseURL: URL?
    /// `SUPABASE_ANON_KEY`. Public by design; empty when not configured yet.
    public var supabaseAnonKey: String
    /// `{DOMAIN}`, the host in room links: `https://{DOMAIN}/r/{slug}?t={token}`.
    public var webDomain: String
    /// Whether `glow://` links are accepted. Debug builds only.
    public var allowsCustomScheme: Bool
    /// PostHog project key. Empty means analytics is a no-op.
    public var posthogKey: String
    public var posthogHost: URL?
    /// Sentry DSN. Empty means error reporting is a no-op.
    public var sentryDSN: String

    public init(
        environment: Environment,
        apiBaseURL: URL,
        supabaseURL: URL? = nil,
        supabaseAnonKey: String = "",
        webDomain: String,
        allowsCustomScheme: Bool,
        posthogKey: String = "",
        posthogHost: URL? = nil,
        sentryDSN: String = "",
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.webDomain = webDomain.lowercased()
        self.allowsCustomScheme = allowsCustomScheme
        self.posthogKey = posthogKey
        self.posthogHost = posthogHost
        self.sentryDSN = sentryDSN
    }

    /// The custom link scheme Debug builds register.
    public static let customScheme = "glow"

    /// A Debug configuration for previews and tests.
    public static let preview = AppConfig(
        environment: .debug,
        apiBaseURL: URL(string: "http://localhost:3000")!,
        supabaseURL: URL(string: "http://127.0.0.1:54421"),
        webDomain: "glow.example",
        allowsCustomScheme: true,
    )
}

// MARK: - Reading Info.plist

public enum AppConfigError: Error, Hashable, CustomStringConvertible {
    case missing(key: String)
    case invalidURL(key: String)
    case insecureAPIURL

    public var description: String {
        switch self {
        case let .missing(key): "Info.plist is missing \(key). Check ios/Glow/Config/*.xcconfig."
        case let .invalidURL(key): "Info.plist \(key) is not a valid URL. Check ios/Glow/Config/*.xcconfig."
        case .insecureAPIURL: "Release builds must talk to the API over https."
        }
    }
}

extension AppConfig {
    /// Info.plist keys. Each one is set from the xcconfig variable in its comment.
    public enum InfoKey {
        public static let apiBaseURL = "GlowAPIBaseURL" // API_BASE_URL
        public static let supabaseURL = "GlowSupabaseURL" // SUPABASE_URL
        public static let supabaseAnonKey = "GlowSupabaseAnonKey" // SUPABASE_ANON_KEY
        public static let webDomain = "GlowWebDomain" // GLOW_WEB_DOMAIN
        public static let posthogKey = "GlowPostHogKey" // POSTHOG_KEY
        public static let posthogHost = "GlowPostHogHost" // POSTHOG_HOST
        public static let sentryDSN = "GlowSentryDSN" // SENTRY_DSN
    }

    /// Builds the configuration from an Info.plist dictionary.
    public init(
        infoDictionary info: [String: Any],
        environment: Environment,
        allowsCustomScheme: Bool,
    ) throws(AppConfigError) {
        func string(_ key: String) -> String {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func url(_ key: String, required: Bool) throws(AppConfigError) -> URL? {
            let value = string(key)
            if value.isEmpty {
                if required {
                    throw .missing(key: key)
                }
                return nil
            }
            guard let url = URL(string: value), url.scheme != nil, url.host() != nil else {
                throw .invalidURL(key: key)
            }
            return url
        }

        guard let apiBaseURL = try url(InfoKey.apiBaseURL, required: true) else { throw .missing(key: InfoKey.apiBaseURL) }
        if environment == .release, apiBaseURL.scheme?.lowercased() != "https" {
            throw .insecureAPIURL
        }
        let webDomain = string(InfoKey.webDomain)
        if webDomain.isEmpty {
            throw .missing(key: InfoKey.webDomain)
        }

        try self.init(
            environment: environment,
            apiBaseURL: apiBaseURL,
            supabaseURL: url(InfoKey.supabaseURL, required: false),
            supabaseAnonKey: string(InfoKey.supabaseAnonKey),
            webDomain: webDomain,
            allowsCustomScheme: allowsCustomScheme,
            posthogKey: string(InfoKey.posthogKey),
            posthogHost: url(InfoKey.posthogHost, required: false),
            sentryDSN: string(InfoKey.sentryDSN),
        )
    }
}
