import APIClient
import AppCore
import Foundation

// Owner: B5. The app target calls `live` in AppComposition; keep its signature.

public enum PushModule {
    /// The push service the app runs on: APNs registration, categories, token upload and
    /// notification taps to Routes.
    public static func live(_ context: ServiceContext) -> any PushService {
        LivePushService(
            api: context.api,
            session: context.session,
            environment: apnsEnvironment(for: context.config),
            appVersion: appVersion(),
            analytics: context.analytics,
            system: LivePushSystem(),
        )
    }

    /// Xcode builds (Debug, `aps-environment` development) get sandbox tokens; TestFlight and
    /// App Store builds (Release, production) get production ones.
    public static func apnsEnvironment(for config: AppConfig) -> Components.Schemas.ApnsEnvironment {
        config.environment == .debug ? .sandbox : .production
    }

    /// "1.0 (42)", at most 32 characters, as the contract allows.
    static func appVersion(bundle: Bundle = .main) -> String? {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short else { return nil }
        let version = build.map { "\(short) (\($0))" } ?? short
        return String(version.prefix(32))
    }
}
