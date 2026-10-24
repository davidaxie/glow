import AppCore
import Foundation
import SwiftUI

// Owner: C1. Where the deck gets its server calls. The app uses the live API from `Dependencies`
// (card photos come from `dependencies.imaging`, B3); tests and previews inject fixtures, and Debug
// builds can launch with a made-up room, whose photos FixtureImagingService draws:
//
//     -GlowDebugDeckFixture 200            a room of 200 made-up people (C1's find test)
//     -GlowDebugDeckFixture quiet          or normal, checkinEnded, paused, viewLimitReached
//     -GlowDebugFakeScreenCapture YES      act as if the screen is being recorded (P12 UI test)

extension EnvironmentValues {
    /// Overrides the deck's server calls. Nil means the live API.
    @Entry var deckService: (any DeckService)?
    /// Hide the deck whenever the app isn't active, so the app switcher's snapshot never holds
    /// anyone's look (C1-D4). Snapshot tests turn it off: they render outside any scene.
    @Entry var deckHidesWhenInactive = true
    /// What time it is, for "time left". Snapshot tests fix it.
    @Entry var deckClock: @Sendable () -> Date = { Date() }
}

@MainActor
extension Dependencies {
    /// The deck service for this environment: an injected one, a Debug fixture, or the live API.
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
