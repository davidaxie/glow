import Foundation
import UserNotifications

// Owner: B5 (Push). This file and Mocks/PreviewPushService.swift change together.

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

    /// The event this notification is about, from its `type` plus `matchId` or `roomId`.
    /// Nil for anything that isn't one of ours.
    public var event: RealtimeEvent? {
        RealtimeEvent(notificationPayload: payload)
    }
}

/// Apple push: permission, device token registration, and notification taps to Routes.
///
/// The live service registers the notification categories at launch, asks Apple for a device
/// token whenever permission is granted, and uploads it to `POST /api/devices` while someone is
/// signed in (sandbox for Xcode builds, production for TestFlight).
public protocol PushService: Sendable {
    func authorization() async -> PushAuthorization
    /// Shows the system prompt (B1's notifications step), then registers for pushes if allowed.
    func requestAuthorization() async throws -> PushAuthorization
    /// Called by the app delegate with the APNs device token.
    func didRegister(deviceToken: Data) async
    func didFailToRegister(_ error: any Error) async
    /// Removes this phone's token from the server, so the signed-in person's pushes stop
    /// arriving here. Call it before signing out, while the session can still reach the API.
    func unregister() async
    /// How to show a notification that arrives while the app is open.
    func foregroundPresentation(for notification: PushNotification) -> UNNotificationPresentationOptions
    /// Where a tapped notification should take the person, if anywhere.
    func route(for notification: PushNotification) -> Route?
}
