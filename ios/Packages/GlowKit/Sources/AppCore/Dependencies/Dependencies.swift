import APIClient
import SwiftUI

/// Every service the app uses, each behind a protocol. Built once by the app target
/// (`AppComposition`) and read by features from the environment:
///
/// ```swift
/// @Environment(\.dependencies) private var dependencies
/// …
/// let fix = try await dependencies.location.currentFix(timeout: .seconds(10))
/// ```
///
/// Previews and tests use `Dependencies.preview(...)`, which is all mocks and never touches the network.
public struct Dependencies: Sendable {
    public var config: AppConfig
    public var api: GlowAPI
    public var session: any SessionService
    public var location: any LocationService
    public var imaging: any ImagingService
    public var push: any PushService
    public var realtime: any RealtimeService
    public var analytics: any Analytics

    public init(
        config: AppConfig,
        api: GlowAPI,
        session: any SessionService,
        location: any LocationService,
        imaging: any ImagingService,
        push: any PushService,
        realtime: any RealtimeService,
        analytics: any Analytics,
    ) {
        self.config = config
        self.api = api
        self.session = session
        self.location = location
        self.imaging = imaging
        self.push = push
        self.realtime = realtime
        self.analytics = analytics
    }

    /// All mocks. Override any one of them for a particular preview or test.
    public static func preview(
        config: AppConfig = .preview,
        api: GlowAPI = .mock(),
        session: any SessionService = PreviewSessionService(),
        location: any LocationService = PreviewLocationService(),
        imaging: any ImagingService = PreviewImagingService(),
        push: any PushService = PreviewPushService(),
        realtime: any RealtimeService = PreviewRealtimeService(),
        analytics: any Analytics = NoopAnalytics(),
    ) -> Dependencies {
        Dependencies(
            config: config,
            api: api,
            session: session,
            location: location,
            imaging: imaging,
            push: push,
            realtime: realtime,
            analytics: analytics,
        )
    }
}

/// What a service module's `live(_:)` factory gets, so factory signatures never have to change
/// when a service needs one more thing.
public struct ServiceContext: Sendable {
    public let config: AppConfig
    public let api: GlowAPI
    public let session: any SessionService
    public let analytics: any Analytics

    public init(config: AppConfig, api: GlowAPI, session: any SessionService, analytics: any Analytics) {
        self.config = config
        self.api = api
        self.session = session
        self.analytics = analytics
    }
}

extension EnvironmentValues {
    /// The app's services. The root view sets the live ones; the default is all mocks, for previews.
    @Entry public var dependencies: Dependencies = .preview()
}
