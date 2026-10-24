import Foundation

// Owner: C4. How the thread is laid out: when a time shows above a message, and which of my
// messages carries "Sent". Pure, so the tests cover it without a screen.

/// One message as a row in the thread.
struct ChatRow: Identifiable, Hashable {
    let message: ChatMessage
    /// "8:15 PM", "Yesterday 8:15 PM" or "Oct 20, 8:15 PM", above the first message after a pause.
    let timeLabel: String?
    /// My newest delivered message, when nothing of theirs came after it.
    let showsSent: Bool
    /// The other person's message right before was theirs too, so the bubbles sit closer.
    let continuesGroup: Bool

    var id: String {
        message.id
    }
}

enum ChatLayout {
    /// A time shows above a message when this much passed since the one before.
    static let pause: TimeInterval = 15 * 60

    static func rows(for items: [ChatMessage], now: Date, calendar: Calendar) -> [ChatRow] {
        let lastSentIndex = items.lastIndex { $0.delivery == .sent }
        let lastMineSent = items.lastIndex { $0.fromMe && $0.delivery == .sent }
        return items.enumerated().map { index, message in
            let previous = index > 0 ? items[index - 1] : nil
            let pause = previous.map { message.createdAt.timeIntervalSince($0.createdAt) >= Self.pause } ?? true
            let showsLabel = pause && message.delivery == .sent
            return ChatRow(
                message: message,
                timeLabel: showsLabel ? label(for: message.createdAt, now: now, calendar: calendar) : nil,
                showsSent: index == lastMineSent && index == lastSentIndex,
                continuesGroup: !showsLabel && previous?.fromMe == message.fromMe,
            )
        }
    }

    static func label(for date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(timeStyle(calendar))
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday \(time)")
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, calendar: calendar, timeZone: calendar.timeZone)
        style.locale = calendar.locale ?? .current
        return date.formatted(style)
    }

    /// "8:15 PM", for accessibility labels and captions.
    static func time(_ date: Date, calendar: Calendar) -> String {
        date.formatted(timeStyle(calendar))
    }

    private static func timeStyle(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar, timeZone: calendar.timeZone)
        style.locale = calendar.locale ?? .current
        return style
    }
}
