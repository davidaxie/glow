import AppCore
import os
import UIKit
import UserNotifications

/// Owns the app's dependencies and router, and forwards push callbacks to the Push service (B5).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let dependencies: Dependencies
    let router: Router
    private let logger = Logger(subsystem: Log.subsystem, category: "app")

    override init() {
        let dependencies = AppComposition.makeDependencies()
        self.dependencies = dependencies
        router = Router(config: dependencies.config, analytics: dependencies.analytics)
        super.init()
    }

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        dependencies.analytics.track(AnalyticsEvent("app_launched"))
        #if DEBUG
            // `scripts/sim.sh allow-push` launches with this argument and taps Allow, so simulated
            // pushes show without going through onboarding. The real ask is B1's notifications step.
            if UserDefaults.standard.bool(forKey: "GlowDebugAskForNotifications") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                }
            }
            // `scripts/sim.sh scan` launches with a room link here, the way the camera hands a
            // universal link straight to the app. It goes through the same Router.open as any link,
            // and waits for onboarding like one. (simctl openurl stops at an "Open in Glow?" prompt.)
            if let link = UserDefaults.standard.string(forKey: "GlowDebugOpenURL"), let url = URL(string: link) {
                router.open(url)
            }
            // `-GlowDebugRoute glow/<matchID>` opens one match's screen (mutual, match, glow or chat)
            // directly, for Simulator proof of Wave 2 screens before push taps and sign-in are live.
            // It goes through the same Router.go as a tapped notification, and waits for onboarding.
            if let value = UserDefaults.standard.string(forKey: "GlowDebugRoute"), let route = DebugRoute.route(for: value) {
                router.go(route)
            }
        #endif
        return true
    }

    // MARK: Remote notifications

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let push = dependencies.push
        Task { await push.didRegister(deviceToken: deviceToken) }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.error("Push registration failed")
        let push = dependencies.push
        Task { await push.didFailToRegister(error) }
    }

    // MARK: UNUserNotificationCenterDelegate

    // The notification center may call these off the main thread, so they're nonisolated and only
    // touch Sendable state before hopping to the main actor.

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        dependencies.push.foregroundPresentation(for: PushNotification(notification.request.content))
    }

    // The completion-handler form, not the async one: UIKit asserts that this completion runs on
    // the main thread (it updates the app's snapshot), and the async form calls it from wherever
    // its task finishes, which crashed the app on a tapped notification (found by D1's
    // PushTapUITests).
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let push = PushNotification(response.notification.request.content)
        let route = dependencies.push.route(for: push)
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            if let route { router.go(route) }
            done()
        }
    }
}

extension PushNotification {
    /// Copies a notification's userInfo as JSON, so it can cross to the Push service safely.
    init(_ content: UNNotificationContent) {
        let json = JSONSerialization.isValidJSONObject(content.userInfo)
            ? (try? JSONSerialization.data(withJSONObject: content.userInfo, options: [.sortedKeys]))
            : nil
        self.init(categoryIdentifier: content.categoryIdentifier, payload: json ?? Data("{}".utf8))
    }
}
