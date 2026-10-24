import Foundation
import UserNotifications

/// Reports permission as already decided, ignores tokens, shows foreground notifications as banners,
/// and maps tapped notifications to Routes exactly like the live service.
public struct PreviewPushService: PushService {
    public var authorizationResult: PushAuthorization

    public init(authorization: PushAuthorization = .authorized) {
        authorizationResult = authorization
    }

    public func authorization() async -> PushAuthorization {
        authorizationResult
    }

    public func requestAuthorization() async throws -> PushAuthorization {
        authorizationResult
    }

    public func didRegister(deviceToken _: Data) async {}
    public func didFailToRegister(_: any Error) async {}
    public func unregister() async {}

    public func foregroundPresentation(for _: PushNotification) -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func route(for notification: PushNotification) -> Route? {
        notification.event?.destination
    }
}
