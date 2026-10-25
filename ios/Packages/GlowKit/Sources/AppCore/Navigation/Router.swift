import Foundation
import Observation
import os

/// The app's navigation state. The root view (in the app target) renders it; feature modules only
/// ever see `NavigateAction`.
///
/// - Until the profile is finished, every Route except `.onboarding` is held as `pendingRoute` and
///   opened once onboarding completes, so a QR code scanned before signing in still works.
///   It lives in memory only and is dropped on sign-out.
/// - Links are entry points: they reset the Rooms stack and close any sheet or takeover.
@MainActor
@Observable
public final class Router {
    public enum Phase: Hashable, Sendable {
        /// Restoring the session at launch.
        case launching
        case onboarding(OnboardingStep)
        /// Signed in with a finished profile: the tabs.
        case main
    }

    public private(set) var phase: Phase = .launching
    public var selectedTab: AppTab = .rooms
    public var roomsPath: [Route] = []
    public var matchesPath: [Route] = []
    public var settingsPath: [Route] = []
    public var blindPath: [Route] = []
    public var sheet: Route?
    public var cover: Route?
    public private(set) var pendingRoute: Route?

    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let logger = Logger(subsystem: Log.subsystem, category: "navigation")

    public init(config: AppConfig, analytics: any Analytics = NoopAnalytics()) {
        self.config = config
        self.analytics = analytics
    }

    // MARK: Navigating

    /// Shows a Route the way its `presentation` says.
    public func go(_ route: Route) {
        if case .gallery = route, config.environment != .debug {
            return
        }

        if route.requiresOnboarding, phase != .main {
            pendingRoute = route
            logger.debug("Holding \(route.name, privacy: .public) until onboarding is finished")
            return
        }
        logger.debug("Go to \(route.name, privacy: .public)")

        switch route.presentation {
        case .onboarding:
            if case let .onboarding(step) = route, phase != .main {
                phase = .onboarding(step)
            }
        case let .tabRoot(tab):
            dismissModals()
            selectedTab = tab
            setPath([], for: tab)
        case let .push(tab):
            dismissModals()
            selectedTab = tab
            var path = path(for: tab)
            if path.last != route {
                path.append(route)
            }
            setPath(path, for: tab)
        case .sheet:
            sheet = route
        case .fullScreen:
            sheet = nil
            cover = route
        }
    }

    /// Opens an incoming link. Returns false if the link isn't one of ours.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let route = DeepLink.route(for: url, config: config) else {
            analytics.track(AnalyticsEvent("deep_link_ignored"))
            logger.notice("Ignored a link that isn't a room link")
            return false
        }
        analytics.track(AnalyticsEvent("deep_link_opened", ["route": .literal("join_room")]))
        guard phase == .main else {
            pendingRoute = route
            return true
        }
        dismissModals()
        selectedTab = .rooms
        roomsPath = [route]
        return true
    }

    public func dismissModals() {
        sheet = nil
        cover = nil
    }

    public func path(for tab: AppTab) -> [Route] {
        switch tab {
        case .rooms: roomsPath
        case .matches: matchesPath
        case .settings: settingsPath
        case .blind: blindPath
        }
    }

    public func setPath(_ path: [Route], for tab: AppTab) {
        switch tab {
        case .rooms: roomsPath = path
        case .matches: matchesPath = path
        case .settings: settingsPath = path
        case .blind: blindPath = path
        }
    }

    // MARK: Session

    /// Moves between launching, onboarding and the tabs as the session changes.
    public func apply(_ state: SessionState) {
        switch state {
        case .restoring:
            phase = .launching
        case .signedOut:
            let wasSignedIn = phase == .main
            resetNavigation()
            if wasSignedIn {
                pendingRoute = nil
            }
            phase = .onboarding(.welcome)
        case let .onboarding(step):
            if phase == .main {
                resetNavigation()
            }
            phase = .onboarding(step)
        case .ready:
            guard phase != .main else { return }
            phase = .main
            if let pending = pendingRoute {
                pendingRoute = nil
                if case .joinRoom = pending {
                    roomsPath = [pending]
                    selectedTab = .rooms
                } else {
                    go(pending)
                }
            }
        }
    }

    private func resetNavigation() {
        dismissModals()
        roomsPath = []
        matchesPath = []
        settingsPath = []
        blindPath = []
        selectedTab = .rooms
    }
}
