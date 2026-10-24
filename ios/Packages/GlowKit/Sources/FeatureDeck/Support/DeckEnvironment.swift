import AppCore
import Foundation
import SwiftUI

// Owner: C1. Where the deck gets its server calls and card photos. The app uses the live API from
// `Dependencies`; tests and previews inject fixtures, and Debug builds can launch with a made-up room:
//
//     -GlowDebugDeckFixture 200            a room of 200 made-up people (C1's find test)
//     -GlowDebugDeckFixture quiet          or normal, checkinEnded, paused, viewLimitReached
//     -GlowDebugFakeScreenCapture YES      act as if the screen is being recorded (P12 UI test)

extension EnvironmentValues {
    /// Overrides the deck's server calls. Nil means the live API.
    @Entry var deckService: (any DeckService)?
    /// Overrides how card photos load. Nil means the live API.
    @Entry var deckImageLoader: (any CardImageLoading)?
    /// Hide the deck whenever the app isn't active, so the app switcher's snapshot never holds
    /// anyone's look (C1-D4). Snapshot tests turn it off: they render outside any scene.
    @Entry var deckHidesWhenInactive = true
}

extension Dependencies {
    /// The deck service for this environment: an injected one, a Debug fixture, or the live API.
    @MainActor
    func deckService(override: (any DeckService)?) -> any DeckService {
        if let override {
            return override
        }
        #if DEBUG
            if let fixture = DeckDebugLaunch.shared.service {
                return fixture
            }
        #endif
        return APIDeckService(api: api)
    }

    @MainActor
    func deckImageLoader(override: (any CardImageLoading)?) -> any CardImageLoading {
        if let override {
            return override
        }
        #if DEBUG
            if DeckDebugLaunch.shared.service != nil {
                return FixtureCardImageLoader()
            }
        #endif
        return APICardImageLoader(api: api)
    }
}

#if DEBUG
    /// Debug-only launch arguments for Simulator runs and UI tests. Compiled out of Release.
    @MainActor
    final class DeckDebugLaunch {
        static let shared = DeckDebugLaunch(defaults: .standard)

        /// One fixture room for the whole launch, so the room home and the deck agree.
        let service: FixtureDeckService?
        let fakesScreenCapture: Bool

        init(defaults: UserDefaults) {
            fakesScreenCapture = defaults.bool(forKey: "GlowDebugFakeScreenCapture")
            guard let value = defaults.string(forKey: "GlowDebugDeckFixture"), !value.isEmpty else {
                service = nil
                return
            }
            if let count = Int(value) {
                service = FixtureDeckService(count: count)
            } else {
                service = FixtureDeckService(scenario: FixtureDeckService.Scenario(rawValue: value) ?? .normal)
            }
        }
    }
#endif
