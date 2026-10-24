import AppCore
import Foundation
import UIKit
import UserNotifications

/// The few system calls the push service makes, behind a protocol so tests can run without
/// a host app (UIApplication and UNUserNotificationCenter need one).
public protocol PushSystem: Sendable {
    func authorizationStatus() async -> PushAuthorization
    /// Shows the system prompt. True if the person allowed notifications.
    func requestAuthorization() async throws -> Bool
    /// Registers the match, glow, message and check-in categories.
    func registerCategories()
    /// Asks Apple for a device token. The app delegate gets it back.
    @MainActor func registerForRemoteNotifications()
    /// Yields each time the app becomes active, until the stream is cancelled.
    func becameActive() -> AsyncStream<Void>
}

/// The real system: UNUserNotificationCenter and UIApplication.
struct LivePushSystem: PushSystem {
    func authorizationStatus() async -> PushAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return PushAuthorization(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> Bool {
        // Alerts and sound only: Glow never uses badges. Time Sensitive needs no extra option,
        // only the entitlement the app already has.
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(PushCategories.all)
    }

    @MainActor func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func becameActive() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = ObserverToken(NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil,
            ) { _ in continuation.yield() })
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer.token) }
        }
    }
}

/// Holds a NotificationCenter observer token so it can be removed from a Sendable closure.
/// The token is only ever passed back to NotificationCenter, which is thread safe.
private final class ObserverToken: @unchecked Sendable {
    let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }
}

extension PushAuthorization {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .authorized, .ephemeral: self = .authorized
        case .provisional: self = .provisional
        case .denied: self = .denied
        case .notDetermined: self = .notDetermined
        @unknown default: self = .notDetermined
        }
    }

    /// Whether Apple will deliver alerts, so it's worth asking for a device token.
    var allowsPush: Bool {
        self == .authorized || self == .provisional
    }
}
