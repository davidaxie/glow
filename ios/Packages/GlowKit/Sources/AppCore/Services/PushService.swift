import Foundation
import UserNotifications

// Owner from Wave 1: B5 (Push). A3 wrote this first shape; B5 may change this file and
// Mocks/PreviewPushService.swift together.

public enum PushAuthorization: Hashable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
}

/// A notification the app received or the person tapped.
///
/// The app delegate turns the notification's `userInfo` into JSON, so this crosses actors safely.
/// Payloads only ever carry the event type and a match or room ID (spec: Events and push).
public struct PushNotification: Hashable, Sendable {
    public let categoryIdentifier: String
    /// The notification's `userInfo` as JSON, including `aps`.
    public let payload: Data

    public init(categoryIdentifier: String, payload: Data) {
        self.categoryIdentifier = categoryIdentifier
        self.payload = payload
    }
}

/// Apple push: permission, device token registration, and notification taps to Routes.
public protocol PushService: Sendable {
    func authorization() async -> PushAuthorization
    func requestAuthorization() async throws -> PushAuthorization
    /// Called by the app delegate with the APNs device token.
    func didRegister(deviceToken: Data) async
    func didFailToRegister(_ error: any Error) async
    /// How to show a notification that arrives while the app is open.
    func foregroundPresentation(for notification: PushNotification) -> UNNotificationPresentationOptions
    /// Where a tapped notification should take the person, if anywhere.
    func route(for notification: PushNotification) -> Route?
}
