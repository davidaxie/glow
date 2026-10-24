import AppCore
import Foundation
import PostHog
#if canImport(Sentry)
    import Sentry
#endif

/// PostHog (and Sentry, once its package is linked) behind AppCore's `Analytics`, configured so
/// neither can collect personal data.
///
/// Each SDK starts only when its key is set; with every key empty this is `NoopAnalytics`.
/// - PostHog: anonymous (never `identify`), no person profiles, no GeoIP, no session replay,
///   no autocapture, no automatic screen views. Event properties are literals, Bools and Ints only,
///   and sensitive-looking keys are dropped anyway.
/// - Sentry: crashes and recorded errors only. No screenshots, view hierarchy, session replay,
///   performance tracing, network or UI breadcrumbs, or default PII. Every event is scrubbed.
///   The sentry-cocoa package is deferred (docs/DECISIONS.md); this code switches on by itself when
///   it's added back to ios/project.yml.
final class LiveAnalytics: Analytics {
    private let posthogEnabled: Bool
    private let sentryEnabled: Bool

    private init(posthogEnabled: Bool, sentryEnabled: Bool) {
        self.posthogEnabled = posthogEnabled
        self.sentryEnabled = sentryEnabled
    }

    static func make(config: AppConfig) -> any Analytics {
        let posthogEnabled = !config.posthogKey.isEmpty
        let sentryEnabled = SentryReporter.isAvailable && !config.sentryDSN.isEmpty
        guard posthogEnabled || sentryEnabled else { return NoopAnalytics() }

        if sentryEnabled {
            SentryReporter.start(dsn: config.sentryDSN, environment: config.environment.rawValue)
        }
        if posthogEnabled {
            startPostHog(key: config.posthogKey, host: config.posthogHost)
        }
        return LiveAnalytics(posthogEnabled: posthogEnabled, sentryEnabled: sentryEnabled)
    }

    func track(_ event: AnalyticsEvent) {
        guard posthogEnabled else { return }
        var properties: [String: Any] = [:]
        for (key, value) in event.properties where !PrivacyScrubber.isSensitiveKey(key) {
            properties[key] = value.foundationValue
        }
        PostHogSDK.shared.capture(event.name, properties: properties)
    }

    func record(_ error: any Error, context: StaticString) {
        guard sentryEnabled else { return }
        SentryReporter.capture(error, context: context.description)
    }

    private static func startPostHog(key: String, host: URL?) {
        let config = PostHogConfig(projectToken: key, host: host?.absoluteString ?? PostHogConfig.defaultHost)
        config.personProfiles = .never
        config.disableGeoIp = true
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true
        config.sessionReplay = false
        config.captureElementInteractions = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        PostHogSDK.shared.setup(config)
    }
}

#if canImport(Sentry)
    /// Sentry crash and error reporting, with every capture surface that could see personal data off.
    enum SentryReporter {
        static let isAvailable = true

        static func start(dsn: String, environment: String) {
            SentrySDK.start { options in
                options.dsn = dsn
                options.environment = environment
                options.sendDefaultPii = false
                options.attachScreenshot = false
                options.attachViewHierarchy = false
                options.sessionReplay.sessionSampleRate = 0
                options.sessionReplay.onErrorSampleRate = 0
                options.tracesSampleRate = 0
                options.enableAutoPerformanceTracing = false
                options.enableNetworkTracking = false
                options.enableNetworkBreadcrumbs = false
                options.enableCaptureFailedRequests = false
                options.enableAutoBreadcrumbTracking = false
                options.enableUserInteractionTracing = false
                options.enableUIViewControllerTracing = false
                options.enableFileIOTracing = false
                options.enableCoreDataTracing = false
                // No breadcrumbs at all: they can carry URLs, screen text and timings.
                options.maxBreadcrumbs = 0
                options.beforeBreadcrumb = { _ in nil }
                options.beforeSend = { event in
                    scrub(event)
                }
            }
        }

        static func capture(_ error: any Error, context: String) {
            SentrySDK.capture(error: error) { scope in
                scope.setTag(value: context, key: "context")
            }
        }

        /// Strips everything from a Sentry event that could hold personal data.
        static func scrub(_ event: Event) -> Event {
            event.user = nil
            event.request = nil
            event.extra = nil
            event.serverName = nil
            if let message = event.message {
                event.message = SentryMessage(formatted: PrivacyScrubber.scrub(message.formatted))
            }
            for exception in event.exceptions ?? [] {
                exception.value = exception.value.map(PrivacyScrubber.scrub)
            }
            event.breadcrumbs = nil
            return event
        }
    }
#else
    /// Sentry isn't linked yet, so error reports go nowhere.
    enum SentryReporter {
        static let isAvailable = false
        static func start(dsn _: String, environment _: String) {}
        static func capture(_: any Error, context _: String) {}
    }
#endif
