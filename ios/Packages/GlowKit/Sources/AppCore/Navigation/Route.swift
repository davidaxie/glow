import Foundation

/// Every screen another module, a link or a notification can open.
///
/// Feature modules never import each other. To move to another module's screen, send a Route:
///
/// ```swift
/// @Environment(\.navigate) private var navigate
/// …
/// navigate(.chat(matchID))
/// ```
///
/// Sheets that belong to one screen (What did you notice, the tap confirm, the blur preview) stay
/// inside their module and don't need a Route. To add one, see "How to add a route" in docs/HANDOFFS.md.
public enum Route: Hashable, Sendable {
    // MARK: Onboarding (B1, FeatureOnboarding)

    /// Welcome, sign in, profile, photos, notifications. Shown until the profile is finished.
    case onboarding(OnboardingStep)

    // MARK: Rooms (B2, FeatureRooms)

    /// The Rooms tab: scan a code or type one.
    case rooms
    /// The in-app QR scanner.
    case scanner
    /// Type a 6-character room code.
    case roomCode
    /// A room link from a QR code, a poster, a universal link or `glow://` in Debug.
    case joinRoom(RoomLink)

    // MARK: Check-in (B3, FeatureCheckIn)

    /// Outfit photo, blur preview and tags, after the location check passed.
    case checkIn(RoomID, JoinTicket)

    // MARK: Deck (C1, FeatureDeck)

    /// The room's home: name, check-in status and time left, Visible or Paused, Leave.
    case roomHome(RoomID)
    /// Today's-look cards.
    case deck(RoomID)

    // MARK: Matches (C2, FeatureMatch)

    /// The Matches tab: active and past matches.
    case matches
    /// The full-screen mutual moment and reveal.
    case mutual(MatchID)
    /// One match: photos, first name, and the Find each other or Just chat choice.
    case match(MatchID)

    // MARK: Glow (C3, FeatureGlow)

    /// The full-screen glow.
    case glow(MatchID)

    // MARK: Chat (C4, FeatureChat)

    case chat(MatchID)

    // MARK: Settings (B1, FeatureSettings)

    /// The Settings tab.
    case settings
    case editProfile
    case editPhotos

    // MARK: Safety (B8, FeatureSafety)

    case pause
    case deleteAccount
    /// The block sheet, from a card, a match or a chat.
    case block(SafetyContext)
    /// The report sheet (reporting also blocks).
    case report(SafetyContext)

    // MARK: Debug (B6, DesignSystem)

    /// Every component in every state. Debug builds only; ignored in Release.
    case gallery
}

/// The app's three tabs once onboarding is done.
public enum AppTab: String, Hashable, Sendable, CaseIterable {
    case rooms
    case matches
    case settings
}

/// How the root presents a Route.
public enum RoutePresentation: Hashable, Sendable {
    /// Replaces everything while onboarding isn't finished.
    case onboarding
    /// Selects a tab and pops it to its root.
    case tabRoot(AppTab)
    /// Pushes onto a tab's navigation stack.
    case push(AppTab)
    /// A sheet over whatever is showing.
    case sheet
    /// A full-screen takeover.
    case fullScreen
}

extension Route: Identifiable {
    public var id: Self {
        self
    }
}

extension Route {
    public var presentation: RoutePresentation {
        switch self {
        case .onboarding: .onboarding
        case .rooms: .tabRoot(.rooms)
        case .scanner, .roomCode, .joinRoom, .checkIn, .roomHome, .deck: .push(.rooms)
        case .matches: .tabRoot(.matches)
        case .match, .chat: .push(.matches)
        case .mutual, .glow: .fullScreen
        case .settings: .tabRoot(.settings)
        case .editProfile, .editPhotos, .pause, .deleteAccount, .gallery: .push(.settings)
        case .block, .report: .sheet
        }
    }

    /// Everything except onboarding itself waits until the profile is finished.
    public var requiresOnboarding: Bool {
        if case .onboarding = self {
            return false
        }
        return true
    }

    /// A stable name for logs and analytics. Never includes IDs, slugs or tokens.
    public var name: String {
        switch self {
        case .onboarding: "onboarding"
        case .rooms: "rooms"
        case .scanner: "scanner"
        case .roomCode: "room_code"
        case .joinRoom: "join_room"
        case .checkIn: "check_in"
        case .roomHome: "room_home"
        case .deck: "deck"
        case .matches: "matches"
        case .mutual: "mutual"
        case .match: "match"
        case .glow: "glow"
        case .chat: "chat"
        case .settings: "settings"
        case .editProfile: "edit_profile"
        case .editPhotos: "edit_photos"
        case .pause: "pause"
        case .deleteAccount: "delete_account"
        case .block: "block"
        case .report: "report"
        case .gallery: "gallery"
        }
    }
}
