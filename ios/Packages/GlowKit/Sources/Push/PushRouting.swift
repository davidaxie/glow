import APIClient
import AppCore
import Foundation
import UserNotifications

/// Turns notifications into Routes and presentation options. Pure, so it's easy to test.
public enum PushRouting {
    /// Where a tapped notification goes: the event's screen, or nowhere if it isn't one of ours.
    public static func route(for notification: PushNotification) -> Route? {
        notification.event?.destination
    }

    /// While the app is open, our notifications show as a banner in the list, with sound.
    /// Anything that isn't ours is shown in the list only, quietly.
    public static func foregroundPresentation(for notification: PushNotification) -> UNNotificationPresentationOptions {
        notification.event == nil ? [.list] : [.banner, .list, .sound]
    }
}

/// The notification categories from contracts/events.json: match, glow, message and check-in.
public enum PushCategories {
    public static var identifiers: [String] {
        GlowEvents.PushCategory.allCases.map(\.rawValue)
    }

    /// No actions: a tap opens the app at the right screen, and nothing can be done from the
    /// lock screen without unlocking. With previews hidden, the lock screen just says "Glow".
    public static var all: Set<UNNotificationCategory> {
        Set(identifiers.map { identifier in
            UNNotificationCategory(
                identifier: identifier,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Glow",
                options: [],
            )
        })
    }
}
