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
            #if DEBUG
                if let model {
                    await DeckAutoplay.run(model)
                }
            #endif
        }
    }
}

#if DEBUG
    /// Debug builds only, on a fixture room: `-GlowDebugDeckAutoplay skip` skips What did you
    /// notice; `tap` then opens a look and taps it (one-sided), so the deck's motion can be recorded
    /// on a headless Simulator. Never touches the live API: it needs `-GlowDebugDeckFixture`.
    @MainActor
    enum DeckAutoplay {
        static func run(_ model: DeckModel) async {
            let launch = DeckDebugLaunch.shared
            guard launch.service != nil, let mode = launch.autoplay else { return }
            try? await Task.sleep(for: .seconds(1.6))
            await model.apply(.none)
            guard mode == "tap" else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard let card = model.cards.dropFirst().first(where: { $0.id != FixtureDeckService.mutualCard && !$0.tappedByMe })
            else { return }
            model.open(card.id)
            try? await Task.sleep(for: .seconds(1.6))
            model.requestTap(card.id)
            try? await Task.sleep(for: .seconds(1.8))
            _ = await model.confirmTap()
        }
    }
#endif

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
