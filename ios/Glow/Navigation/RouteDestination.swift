import AppCore
import DesignSystem
import FeatureChat
import FeatureCheckIn
import FeatureDeck
import FeatureGlow
import FeatureMatch
import FeatureOnboarding
import FeatureRooms
import FeatureSafety
import FeatureSettings
import SwiftUI

/// The screen for each Route: the one place that knows which module draws which screen.
/// To add a route, see "How to add a route" in docs/HANDOFFS.md.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case let .onboarding(step): OnboardingFlowView(step: step)
        case .rooms: RoomsHomeView()
        case .scanner: RoomScannerView()
        case .roomCode: RoomCodeEntryView()
        case let .joinRoom(link): RoomJoinView(link: link)
        case let .checkIn(room, ticket): CheckInView(roomID: room, ticket: ticket)
        case let .roomHome(room): RoomHomeView(roomID: room)
        case let .deck(room): DeckView(roomID: room)
        case .matches: MatchesListView()
        case let .mutual(match): MutualMomentView(matchID: match)
        case let .match(match): MatchView(matchID: match)
        case let .glow(match): GlowView(matchID: match)
        case let .chat(match): ChatView(matchID: match)
        case .settings: SettingsView()
        case .editProfile: EditProfileView()
        case .editPhotos: EditPhotosView()
        case .pause: PauseView()
        case .deleteAccount: DeleteAccountView()
        case let .block(context): BlockSheet(context: context)
        case let .report(context): ReportSheet(context: context)
        case .gallery: GalleryView()
        }
    }
}
