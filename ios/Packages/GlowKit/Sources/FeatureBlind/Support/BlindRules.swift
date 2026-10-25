import AppCore
import CoreGraphics
import Foundation

// Owner: X2. Pure helpers ported from Double Blind's DeckRules, DropRules, ChatRules and
// SafetyRules, so every rule the screens show is unit tested.

enum BlindDeckRules {
    static let dropMinimum = BlindRulesConstants.dropMinimumRightSwipes
    static let dailyRightLimit = BlindRulesConstants.dailyRightLimit

    /// "3 more to open your drop", or nil once there are enough.
    static func dropProgressText(rightCount: Int) -> String? {
        let missing = dropMinimum - rightCount
        guard missing > 0 else { return nil }
        return missing == 1
            ? String(localized: "1 more to open your drop")
            : String(localized: "\(missing) more to open your drop")
    }

    static func remainingText(_ rightRemaining: Int) -> String {
        rightRemaining == 1
            ? String(localized: "1 right swipe left today")
            : String(localized: "\(rightRemaining) right swipes left today")
    }

    /// How many of the five drop-progress marks are filled.
    static func filledDots(rightCount: Int) -> Int {
        min(max(rightCount, 0), dropMinimum)
    }

    /// The server counts right swipes per UTC day (B4), so the cap resets at the next 00:00 UTC.
    static func nextReset(after now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86400)
    }

    /// "Back at 5:00 PM", in the viewer's own time zone.
    static func resetText(now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        return String(localized: "Back at \(nextReset(after: now).formatted(style))")
    }
}

/// Signed photo links expire (Glow signs them for 60 seconds). A card whose photo hasn't loaded is
/// dropped a little before its link dies, instead of showing a broken image.
enum BlindLink {
    /// When a link carries no readable expiry: treat it as short-lived.
    static let fallbackLifetime: TimeInterval = 50
    /// A not-yet-loaded card whose link has less than this left is replaced with a fresh one.
    static let staleMargin: TimeInterval = 8

    /// Glow's `exp` query item (Unix seconds), or a JWT `token` query item's `exp`.
    static func expiry(of urlString: String) -> Date? {
        if urlString.hasPrefix("mock://") {
            return .distantFuture
        }
        guard let items = URLComponents(string: urlString)?.queryItems else { return nil }
        if let exp = items.first(where: { $0.name == "exp" })?.value, let seconds = TimeInterval(exp) {
            return Date(timeIntervalSince1970: seconds)
        }
        guard let token = items.first(where: { $0.name == "token" })?.value else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while !base64.count.isMultiple(of: 4) {
            base64 += "="
        }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func expiry(of urlString: String, receivedAt: Date) -> Date {
        expiry(of: urlString) ?? receivedAt.addingTimeInterval(fallbackLifetime)
    }
}

/// What a finished drag means. Pure, so the thresholds are unit tested.
enum BlindSwipeGesture {
    /// Drag this far sideways to commit a pass or a like.
    static let commitX: CGFloat = 110
    /// Drag this far up to commit a love.
    static let commitUp: CGFloat = 120
    /// A flick: the predicted end is this far out and the finger already moved a little the same way.
    static let flickDistance: CGFloat = 280
    static let flickMinimumTravel: CGFloat = 36

    /// nil means "spring back".
    static func intent(translation: CGSize, predicted: CGSize) -> BlindSwipeKind? {
        let dx = translation.width
        let dy = translation.height
        let upwards = dy < 0 && abs(dy) > abs(dx) * 1.3
        if upwards, -dy > commitUp {
            return .love
        }
        if upwards, -predicted.height > flickDistance, -dy > flickMinimumTravel {
            return .love
        }
        if dx > commitX {
            return .like
        }
        if dx < -commitX {
            return .pass
        }
        if predicted.width > flickDistance, dx > flickMinimumTravel, !upwards {
            return .like
        }
        if predicted.width < -flickDistance, dx < -flickMinimumTravel, !upwards {
            return .pass
        }
        return nil
    }

    /// How strongly each stamp (Pass, Like, Love) shows while dragging, 0 to 1.
    static func stamps(translation: CGSize) -> (pass: Double, like: Double, love: Double) {
        let dx = translation.width
        let dy = translation.height
        let upwards = dy < 0 && abs(dy) > abs(dx) * 1.3
        func clamp(_ value: CGFloat) -> Double {
            Double(min(max(value, 0), 1))
        }
        if upwards {
            return (0, 0, clamp(-dy / commitUp))
        }
        return (clamp(-dx / commitX), clamp(dx / commitX), 0)
    }
}

enum BlindDropRules {
    /// What the drop screen shows, decided from the server's status alone.
    enum Mode: Equatable, Sendable {
        /// Fewer than 5 right swipes: nothing can open yet.
        case needSwipes(remaining: Int)
        /// A live drop that hasn't happened yet today: countdown only.
        case waiting
        /// Demo mode (stage only): the drop opens now.
        case demo
        /// A live drop whose time has come.
        case ready
    }

    static func mode(for status: BlindDropStatus) -> Mode {
        guard status.canDrop else {
            return .needSwipes(remaining: swipesToGo(rightCount: status.rightCount))
        }
        if status.demo {
            return .demo
        }
        return status.ready ? .ready : .waiting
    }

    static func swipesToGo(rightCount: Int) -> Int {
        max(0, BlindRulesConstants.dropMinimumRightSwipes - rightCount)
    }

    static func openedText(_ opened: Int) -> String {
        switch opened {
        case 0: String(localized: "Nothing new this time.")
        case 1: String(localized: "1 new chat.")
        default: String(localized: "\(opened) new chats.")
        }
    }

    /// "03:12:09". Whole seconds, never negative.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// For VoiceOver: "3 hours, 12 minutes".
    static func countdownSpoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        var parts: [String] = []
        if hours > 0 {
            parts.append(hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours"))
        }
        if minutes > 0 {
            parts.append(minutes == 1 ? String(localized: "1 minute") : String(localized: "\(minutes) minutes"))
        }
        if parts.isEmpty {
            parts.append(String(localized: "under a minute"))
        }
        return parts.joined(separator: ", ")
    }

    static func progressText(rightCount: Int) -> String {
        let remaining = swipesToGo(rightCount: rightCount)
        if remaining == 0 {
            return String(localized: "You're in tonight's drop.")
        }
        return remaining == 1
            ? String(localized: "Like 1 more person to open your drop.")
            : String(localized: "Like \(remaining) more people to open your drop.")
    }

    /// The codenames to reveal, straight from the server's answer: the chats new to me (E3).
    static func revealNames(_ result: BlindDropResult) -> [String] {
        let names = result.chats.map(\.codename)
        guard result.opened > names.count else { return names }
        return names + Array(repeating: String(localized: "New chat"), count: result.opened - names.count)
    }
}

enum BlindChatRules {
    static func preview(_ chat: BlindChatSummary) -> String {
        guard let last = chat.lastMessage else { return String(localized: "Say hello.") }
        return last.mine ? String(localized: "You: \(last.text)") : last.text
    }

    /// The header pill. B5: before the reveal it depends only on MY tap.
    enum Pill: Equatable {
        case reveal, waiting, revealed
    }

    static func revealPill(_ detail: BlindChatDetail?) -> Pill {
        guard let detail else { return .reveal }
        if detail.status == .revealed {
            return .revealed
        }
        return detail.iTappedReveal ? .waiting : .reveal
    }

    static func canSend(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= BlindRulesConstants.messageMaxLength
    }

    /// Short label under the codename for chats that aren't plain open ones.
    static func statusLabel(_ status: BlindChatStatus) -> String? {
        switch status {
        case .open: nil
        case .left: String(localized: "They left")
        case .revealed: String(localized: "Revealed")
        }
    }

    /// The banner on top of the chats: what the drop is doing, from the server's status.
    static func dropBanner(_ status: BlindDropStatus, now: Date = Date(), hasChats: Bool = false) -> (title: String, detail: String) {
        if !status.canDrop {
            let remaining = BlindDropRules.swipesToGo(rightCount: status.rightCount)
            let who = remaining == 1 ? String(localized: "1 more person") : String(localized: "\(remaining) more people")
            return (
                String(localized: "Your drop"),
                hasChats ? String(localized: "Like \(who) to open your own drop") : String(localized: "Like \(who) to open your drop"),
            )
        }
        if status.ready {
            return (String(localized: "Your drop is ready"), String(localized: "Tap to open it"))
        }
        let seconds = max(0, status.nextDropAt.timeIntervalSince(now))
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let text = hours > 0 ? "\(hours)h \(minutes)m" : "\(max(minutes, 1))m"
        return (String(localized: "Tonight's drop"), String(localized: "Opens in \(text)"))
    }

    /// "now", "5m", "3h", or a short date.
    static func timeText(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return String(localized: "now")
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// What the chat menu offers for a chat in a given state.
struct BlindMenuItems: Equatable {
    var guess: Bool
    var report: Bool
    var leave: Bool
    var block: Bool

    init(status: BlindChatStatus) {
        switch status {
        case .open:
            guess = true
            report = true
            leave = true
            block = true
        case .left, .revealed:
            // Nothing left to guess; a revealed chat can only be blocked, not left.
            guess = false
            report = true
            leave = false
            block = true
        }
    }
}

enum BlindSafetyRules {
    static let reasons = [
        String(localized: "Harassment"),
        String(localized: "Spam or scam"),
        String(localized: "Inappropriate content"),
        String(localized: "Underage"),
        String(localized: "Something else"),
    ]
    static let maxDetailsLength = 300

    /// The text sent with a report: the chosen reason, plus optional details after a colon. nil when
    /// no reason is chosen. Never longer than the server accepts.
    static func reportText(choice: String?, details: String) -> String? {
        guard let choice, !choice.isEmpty else { return nil }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? choice : "\(choice): \(trimmed)"
        return String(text.prefix(BlindRulesConstants.reportMaxLength))
    }
}

/// Where the Reveal flow is. B5: `waiting` is all the tapper ever sees after a one-sided tap.
enum BlindRevealPhase: Equatable, Sendable {
    case ready
    case sending
    case waiting
    case revealed
    /// They left (or the chat was closed). Reveal can never happen.
    case left
    case failed(String)

    static func phase(for detail: BlindChatDetail) -> BlindRevealPhase {
        if detail.theyLeft {
            return .left
        }
        switch detail.status {
        case .revealed: return .revealed
        case .left: return .left
        case .open: return detail.iTappedReveal ? .waiting : .ready
        }
    }

    static func phase(after status: BlindChatStatus) -> BlindRevealPhase {
        switch status {
        case .revealed: .revealed
        case .left: .left
        case .open: .waiting
        }
    }
}
