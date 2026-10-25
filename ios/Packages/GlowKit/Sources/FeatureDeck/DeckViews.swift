import AppCore
import DesignSystem
import SwiftUI

// Owner: C1. The two screens the app shows for `.roomHome` and `.deck`. Keep these public
// initializers: ios/Glow/Navigation/RouteDestination.swift calls them.

/// The room's home: name, check-in status and time left, Visible or Paused, Leave.
public struct RoomHomeView: View {
    public let roomID: RoomID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.deckService) private var injectedService
    @State private var model: RoomHomeModel?

    public init(roomID: RoomID) {
        self.roomID = roomID
    }

    public var body: some View {
        ZStack {
            if let model {
                RoomHomeScreen(model: model)
            } else {
                Color.glowBackground.ignoresSafeArea()
            }
        }
        .onAppear {
            guard model == nil else { return }
            model = RoomHomeModel(
                roomID: roomID,
                service: dependencies.deckService(override: injectedService),
                analytics: dependencies.analytics,
            )
        }
    }
}

/// Today's-look cards: What did you notice, the grid, the enlarged card and tapping.
public struct DeckView: View {
    public let roomID: RoomID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.deckService) private var injectedService
    @State private var model: DeckModel?
    @State private var checkInAgain: Route = .scanner

    public init(roomID: RoomID) {
        self.roomID = roomID
    }

    public var body: some View {
        ZStack {
            if let model {
                DeckScreen(model: model, checkInAgain: checkInAgain)
            } else {
                Color.glowBackground.ignoresSafeArea()
            }
        }
        .modifier(DebugLaunch())
        .onAppear {
            guard model == nil else { return }
            model = DeckModel(
                roomID: roomID,
                service: dependencies.deckService(override: injectedService),
                analytics: dependencies.analytics,
            )
        }
        .task {
            let me = await dependencies.session.currentProfile()
            await model?.start(showMe: me.map { Set($0.profile.showMe) }, viewerCode: me?.profile.viewerCode)
            if let slug = model?.roomSlug {
                checkInAgain = .joinRoom(RoomLink(slug: slug, token: nil))
            }
        }
    }
}

/// Debug builds only: `-GlowDebugFakeScreenCapture YES` makes the deck behave as if the screen is
/// being recorded (the P12 UI test), and `-GlowDebugDeckFixture` draws the made-up room's photos
/// on the phone instead of fetching them.
private struct DebugLaunch: ViewModifier {
    @Environment(\.dependencies) private var dependencies

    func body(content: Content) -> some View {
        #if DEBUG
            var fixed = dependencies
            if DeckDebugLaunch.shared.service != nil {
                fixed.imaging = FixtureImagingService()
            }
            let fakesCapture = DeckDebugLaunch.shared.fakesScreenCapture
            return content
                .environment(\.dependencies, fixed)
                .transformEnvironment(\.isSceneCaptured) { captured in
                    captured = captured || fakesCapture
                }
        #else
            return content
        #endif
    }
}

#Preview("Room home") {
    NavigationStack { RoomHomeView(roomID: RoomID(rawValue: "de000000-0000-4000-8000-000000000001")) }
        .environment(\.deckService, FixtureDeckService())
        .environment(\.dependencies, .preview(imaging: FixtureImagingService()))
        .preferredColorScheme(.dark)
}

#Preview("Deck") {
    NavigationStack { DeckView(roomID: RoomID(rawValue: "de000000-0000-4000-8000-000000000001")) }
        .environment(\.deckService, FixtureDeckService(count: 200))
        .environment(\.dependencies, .preview(imaging: FixtureImagingService()))
        .preferredColorScheme(.dark)
}
