import DesignSystem
import Foundation
import Testing
import UIKit
@testable import FeatureGlow

// Owner: C3. "Brightness is always restored" (Done when). The glow surface raises brightness while
// `wantsFullBrightness` is true and the screen is in front, and puts the person's own level back
// the moment it isn't. These drive the brightness controller exactly the way the surface's
// modifier does, through every way a glow can end.

@MainActor
final class FakeScreen: GlowBrightnessAdjustable {
    var brightness: CGFloat

    init(_ brightness: CGFloat) {
        self.brightness = brightness
    }
}

/// What `.glowFullBrightness(model.wantsFullBrightness)` does: raise when it turns on, release
/// when it turns off.
@MainActor
struct SurfaceDriver {
    let controller: GlowBrightness
    let screen: FakeScreen
    let holder = UUID()

    func follow(_ model: GlowModel) {
        if model.wantsFullBrightness {
            controller.raise(for: holder, on: screen)
        } else {
            controller.release(holder)
        }
    }
}

@MainActor
struct BrightnessTests {
    enum Exit: CaseIterable {
        case bothMet, endGlow, switchToChat, timeRanOut, matchEnded, leftTheScreen
    }

    @Test(arguments: Exit.allCases)
    func everyWayOutRestoresThePersonsOwnBrightness(_ exit: Exit) async {
        let clock = TestClock()
        let client = ScriptedGlowClient(
            glow: [.success(.test())],
            met: [.success(.test(status: .met))],
            end: [.success(.test(status: .canceled))],
        )
        let harness = Harness(client, clock: clock)
        let screen = FakeScreen(0.3)
        let surface = SurfaceDriver(controller: GlowBrightness(), screen: screen)

        harness.model.isVisible = true
        await harness.model.refresh()
        surface.follow(harness.model)
        #expect(screen.brightness == 1)

        switch exit {
        case .bothMet:
            await harness.model.markMet()
        case .endGlow:
            _ = await harness.model.end(as: .cancel)
        case .switchToChat:
            _ = await harness.model.end(as: .switchToChat)
        case .timeRanOut:
            clock.advance(by: 13 * 60)
            await harness.model.tick()
        case .matchEnded:
            client.then(glow: .failure(.notFound))
            await harness.model.refresh()
            await harness.model.refresh()
        case .leftTheScreen:
            harness.model.isVisible = false
        }
        surface.follow(harness.model)
        #expect(screen.brightness == 0.3)
        #expect(!surface.controller.isRaised)
    }

    @Test func aBrighterScreenIsNeverDimmed() {
        let screen = FakeScreen(1)
        let controller = GlowBrightness(raisedLevel: 1)
        let holder = UUID()
        controller.raise(for: holder, on: screen)
        #expect(screen.brightness == 1)
        controller.release(holder)
        #expect(screen.brightness == 1)
    }

    @Test func twoGlowScreensOverlappingDuringATransitionStillRestore() {
        let screen = FakeScreen(0.45)
        let controller = GlowBrightness()
        let first = UUID()
        let second = UUID()
        controller.raise(for: first, on: screen)
        controller.raise(for: second, on: screen)
        controller.release(first)
        #expect(screen.brightness == 1)
        controller.release(second)
        #expect(screen.brightness == 0.45)
    }
}
