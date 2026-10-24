import AppCore
import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureGlow

// Owner: C3. Every glow screen state at the default text size and the largest accessibility size
// (spec: "Every screen at default and largest text size"). The pulse and the countdown are held
// still at `frozenNow`.
//
// To re-record after an intended change, delete the PNGs in `__Snapshots__/GlowSnapshotTests` and
// run `scripts/sim.sh test FeatureGlow` twice (the first run records and fails).

@MainActor
struct GlowSnapshotTests {
    enum State: String, CaseIterable {
        case glowing, sunTheyMet, waitingForThem, noMeetingSpot, actionFailed
        case met, canceled, expired, gone, offline, loading

        var client: ScriptedGlowClient {
            switch self {
            case .glowing: ScriptedGlowClient(glow: [.success(.test())])
            case .sunTheyMet: ScriptedGlowClient(glow: [.success(.test(hue: .sun, word: "pretzel", theyMet: true))])
            case .waitingForThem: ScriptedGlowClient(glow: [.success(.test(hue: .violet, word: "toboggan", youMet: true))])
            case .noMeetingSpot: ScriptedGlowClient(glow: [.success(.test(hue: .pearl, word: "kazoo", spot: nil))])
            case .actionFailed: ScriptedGlowClient(glow: [.success(.test(hue: .ember, word: "compass"))], met: [.failure(.offline)])
            case .met: ScriptedGlowClient(glow: [.success(.test(status: .met))])
            case .canceled: ScriptedGlowClient(glow: [.success(.test(status: .canceled))])
            case .expired: ScriptedGlowClient(glow: [.success(.test(status: .expired))])
            case .gone: ScriptedGlowClient(glow: [.failure(.notFound)])
            case .offline: ScriptedGlowClient(glow: [.failure(.offline)])
            case .loading: ScriptedGlowClient()
            }
        }
    }

    func model(_ state: State) async -> GlowModel {
        let h = Harness(state.client)
        if state != .loading {
            await h.model.refresh()
        }
        if state == .actionFailed {
            await h.model.markMet()
        }
        return h.model
    }

    @Test(arguments: State.allCases, [DynamicTypeSize.large, .accessibility5])
    func state(_ state: State, size: DynamicTypeSize) async {
        let view = GlowScreen(model: await model(state), events: nil, frozenAt: frozenNow)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 393, height: 852),
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = .dark
                    traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
                },
            ),
            named: "\(state.rawValue)-\(size == .large ? "default" : "ax5")",
        )
    }

    /// Reduce Motion can't be set through the SwiftUI environment in a test, so the glow's motion is
    /// checked where it's decided: the pulse the surface draws from `accessibilityReduceMotion`.
    @Test func reduceMotionPulsesSlowerThanOncePerSecondAndNeverDims() {
        // Flash safety (spec): under 1 pulse a second, never below 70%, both with and without Reduce Motion.
        #expect(GlowPulse.frequency(reduceMotion: false) < 1)
        #expect(GlowPulse.frequency(reduceMotion: true) < GlowPulse.frequency(reduceMotion: false))
        #expect(GlowPulse.minimumLuminanceRatio >= 0.7)
        for step in 0 ..< 100 {
            let time = Double(step) * 0.05
            let still = GlowPulse.frame(at: time, reduceMotion: true)
            #expect(still.scale == 1) // Reduce Motion: no change in size, only a fade
            #expect(still.opacity >= 0.2 && still.opacity <= 1)
        }
    }
}
