import APIClient
import AppCore
import Foundation
import GlowRealtime
import Imaging
import Location
import Push
import Session

/// The composition root: the one place the live services are built.
///
/// Each service comes from its own module's `live` factory, so owners swap in real
/// implementations inside their module without touching this file.
enum AppComposition {
    static func makeDependencies() -> Dependencies {
        let config = loadConfig()
        let analytics = LiveAnalytics.make(config: config)
        let session = SessionModule.live(config: config, analytics: analytics)
        let api = GlowAPI.live(baseURL: config.apiBaseURL, tokens: session)
        let context = ServiceContext(config: config, api: api, session: session, analytics: analytics)
        return Dependencies(
            config: config,
            api: api,
            session: session,
            location: LocationModule.live(context),
            imaging: ImagingModule.live(context),
            push: PushModule.live(context),
            realtime: RealtimeModule.live(context),
            analytics: analytics,
        )
    }

    static func loadConfig(bundle: Bundle = .main) -> AppConfig {
        #if DEBUG
            let environment = AppConfig.Environment.debug
            let allowsCustomScheme = true
        #else
            let environment = AppConfig.Environment.release
            let allowsCustomScheme = false
        #endif
        do {
            return try AppConfig(
                infoDictionary: bundle.infoDictionary ?? [:],
                environment: environment,
                allowsCustomScheme: allowsCustomScheme,
            )
        } catch {
            // A misconfigured build should never reach anyone's phone.
            fatalError("Glow is misconfigured: \(error)")
        }
    }
}
