import APIClient
import Foundation

// Owner: C1. Every word FeatureDeck shows, in one place for D4's copy pass (docs/HANDOFFS.md,
// C1 · Notes for D4). Voice (spec): warm, calm, never pushy. No names, ever: cards have none.

enum DeckCopy {
    // MARK: Room home

    static let seeLooks = String(localized: "See today's looks")
    static let checkedIn = String(localized: "You're checked in")
    static let checkinEnded = String(localized: "Your check-in ended")
    static let cardRemoved = String(localized: "Your card is hidden")
    static let cardRemovedDetail = String(localized: "The room's hosts took your card down. You can check in again with a new photo.")
    static let roomEnded = String(localized: "This room has ended")
    static let roomPaused = String(localized: "This room is taking a break")
    static let checkInAgain = String(localized: "Check in again")
    static let visible = String(localized: "Visible")
    static let visibleDetail = String(localized: "People here can see your look.")
    static let pausedDetail = String(localized: "Paused. Nobody sees you, and you don't see anyone.")
    static let leave = String(localized: "Leave room")
    static let leaveTitle = String(localized: "Leave this room?")
    static let leaveMessage = String(localized: "Your card leaves every deck right away.")
    static let leaveConfirm = String(localized: "Leave")
    static let stay = String(localized: "Stay")
    static let roomLoadFailed = String(localized: "Couldn't load this room.")
    static let tryAgain = String(localized: "Try again")
    static let pauseFailed = String(localized: "Couldn't change that. Try again in a moment.")
    static let leaveFailed = String(localized: "Couldn't leave just now. Try again in a moment.")

    static func timeLeft(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded(.up)))
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0
                ? String(localized: "\(hours) h left")
                : String(localized: "\(hours) h \(rest) min left")
        }
        return String(localized: "\(minutes) min left")
    }

    static func tapsLeft(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No taps left today")
        case 1: String(localized: "1 tap left today")
        default: String(localized: "\(count) taps left today")
        }
    }

    // MARK: What did you notice

    static let noticeTitle = String(localized: "What did you notice?")
    static let noticeSubtitle = String(localized: "Pick anything you remember. Skip what you don't.")
    static let noticeWho = String(localized: "Who")
    static let noticeTop = String(localized: "Top color")
    static let noticeHairLength = String(localized: "Hair length")
    static let noticeHairColor = String(localized: "Hair color")
    static let noticeExtras = String(localized: "Anything else")
    static let noticeClear = String(localized: "Clear")
    static let noticeSkip = String(localized: "Skip, show everyone")

    static func noticeApply(_ filters: Int) -> String {
        filters == 0 ? String(localized: "Show everyone") : String(localized: "Show looks")
    }

    // MARK: Deck

    static let deckTitle = String(localized: "Today's looks")
    static let changeNoticed = String(localized: "What did you notice?")
    static let editNoticed = String(localized: "Change")
    static let loadMoreFailed = String(localized: "Couldn't load more looks.")
    static let deckFailed = String(localized: "Couldn't load the looks.")
    static let offline = String(localized: "You're offline. Looks come back when you're connected.")

    static func viewsLeft(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "That's every new look for today")
        case 1: String(localized: "1 new look left today")
        default: String(localized: "\(count) new looks left today")
        }
    }

    // MARK: Enlarged card and tapping

    static let thatsThem = String(localized: "That's them")
    static let youTappedThem = String(localized: "You tapped them")
    static let close = String(localized: "Close")
    static let more = String(localized: "More")
    static let block = String(localized: "Block")
    static let report = String(localized: "Report")
    static let confirmTitle = String(localized: "That's them?")
    static let confirmMessage = String(localized: "They won't know unless they tap you too.")
    static let confirmTap = String(localized: "Tap")
    static let notYet = String(localized: "Not yet")
    static let tapSent = String(localized: "Sent. It stays secret unless they tap you too.")
    static let noTapsLeft = String(localized: "You've used today's taps in this room.")
    static let cardGone = String(localized: "That look isn't in the deck anymore.")
    static let tapFailed = String(localized: "Couldn't send that. Try again in a moment.")
    static let slowDown = String(localized: "Slow down a little and try again.")
    static let loadingLooks = String(localized: "Loading looks")
    static let todaysLook = String(localized: "Today's look")

    // MARK: Empty states

    static let emptyNoMatchTitle = String(localized: "Nobody fits that yet.")
    static let emptyNoMatchMessage = String(localized: "Try fewer details.")
    static let emptyQuietTitle = String(localized: "It's quiet here.")
    static let emptyQuietMessage = String(localized: "Nobody else fits you yet. New looks appear as people check in.")
    static let emptyCheckinTitle = String(localized: "Your check-in ended.")
    static let emptyCheckinMessage = String(localized: "Check in again with today's look to see who's here.")
    static let emptyPausedTitle = String(localized: "You're paused.")
    static let emptyPausedMessage = String(localized: "Nobody sees you, and you don't see anyone. Be visible again to see today's looks.")
    static let emptyPausedAction = String(localized: "Be visible")
    static let emptyViewsTitle = String(localized: "That's everyone for today.")
    static let emptyViewsMessage = String(localized: "You've seen today's new looks in this room. Looks you've already seen stay here.")

    // MARK: Privacy (P12)

    static let hiddenTitle = String(localized: "Looks are hidden")
    static let hiddenMessage = String(localized: "Glow hides the deck while your screen is recorded or shared.")
    static let screenshotNote = String(localized: "Looks stay in Glow. Screenshots are noted, and every photo carries your code.")

    // MARK: Tags

    static func name(_ color: TopColor) -> String {
        switch color {
        case .black: String(localized: "Black")
        case .white: String(localized: "White")
        case .gray: String(localized: "Gray")
        case .red: String(localized: "Red")
        case .pink: String(localized: "Pink")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        }
    }

    static func name(_ length: HairLength) -> String {
        switch length {
        case .short: String(localized: "Short")
        case .medium: String(localized: "Medium")
        case .long: String(localized: "Long")
        }
    }

    static func name(_ color: HairColor) -> String {
        switch color {
        case .black: String(localized: "Black")
        case .brown: String(localized: "Brown")
        case .blonde: String(localized: "Blonde")
        case .red: String(localized: "Red")
        case .gray: String(localized: "Gray")
        case .dyed: String(localized: "Dyed")
        }
    }

    static func name(_ extra: CardExtra) -> String {
        switch extra {
        case .glasses: String(localized: "Glasses")
        case .hat: String(localized: "Hat")
        case .beard: String(localized: "Beard")
        case .headphones: String(localized: "Headphones")
        case .backpack: String(localized: "Backpack")
        }
    }

    static func name(_ gender: Gender) -> String {
        switch gender {
        case .woman: String(localized: "A woman")
        case .man: String(localized: "A man")
        case .nonbinary: String(localized: "Nonbinary")
        }
    }

    /// What VoiceOver reads for a card: its tags in a sentence, for example "Green top, short blonde
    /// hair, glasses, headphones". Never a name, a distance or anything about the person.
    static func describe(_ tags: CardTags) -> String {
        var parts = [String(localized: "\(name(tags.topColor)) top")]
        switch (tags.hairLength, tags.hairColor) {
        case let (length?, color?):
            parts.append(String(localized: "\(name(length).lowercased()) \(name(color).lowercased()) hair"))
        case let (length?, nil):
            parts.append(String(localized: "\(name(length).lowercased()) hair"))
        case let (nil, color?):
            parts.append(String(localized: "\(name(color).lowercased()) hair"))
        case (nil, nil):
            break
        }
        parts += CardExtra.allCases.filter(tags.extras.contains).map { name($0).lowercased() }
        return parts.joined(separator: ", ")
    }
}

extension CardExtra {
    /// An SF Symbol for the extra, where iOS 17 has one.
    var deckSymbol: String? {
        switch self {
        case .glasses: "eyeglasses"
        case .headphones: "headphones"
        case .backpack: "backpack"
        case .beard: "mustache"
        case .hat: nil
        }
    }
}
