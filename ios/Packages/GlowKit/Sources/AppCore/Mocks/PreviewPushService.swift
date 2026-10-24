import Foundation
import UserNotifications

/// Reports permission as already decided, ignores tokens, and shows foreground notifications as banners.
/// Maps nothing to a Route until B5 parses payloads from contracts/events.json.
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

    public func foregroundPresentation(for _: PushNotification) -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public func route(for _: PushNotification) -> Route? {
        nil
    }
}
