import Foundation
import Testing
@testable import DesignSystem

/// "GlowSurface respects Reduce Motion and always restores brightness" (B6 brief).
@MainActor
struct GlowBrightnessTests {
    final class FakeScreen: GlowBrightnessAdjustable {
        var brightness: CGFloat
        init(_ brightness: CGFloat) {
            self.brightness = brightness
        }
    }

    @Test func raisesThenRestoresThePersonsOwnLevel() {
        let screen = FakeScreen(0.35)
        let brightness = GlowBrightness()
        let glow = UUID()
        brightness.raise(for: glow, on: screen)
        #expect(screen.brightness == 1)
        #expect(brightness.levelToRestore == 0.35)
        brightness.release(glow)
        #expect(screen.brightness == 0.35)
        #expect(!brightness.isRaised)
    }

    @Test func raisingTwiceNeverSavesTheRaisedLevel() {
        let screen = FakeScreen(0.2)
        let brightness = GlowBrightness()
        let glow = UUID()
        brightness.raise(for: glow, on: screen)
        brightness.raise(for: glow, on: screen)
        brightness.release(glow)
        #expect(screen.brightness == 0.2)
    }

    @Test func overlappingViewsRestoreOnlyWhenTheLastOneGoes() {
        // A transition shows the new glow view before the old one disappears.
        let screen = FakeScreen(0.5)
        let brightness = GlowBrightness()
        let old = UUID(), new = UUID()
        brightness.raise(for: old, on: screen)
        brightness.raise(for: new, on: screen)
        brightness.release(old)
        #expect(screen.brightness == 1)
        brightness.release(new)
        #expect(screen.brightness == 0.5)
    }

    @Test func comingBackPicksUpALevelChangedInControlCenter() {
        let screen = FakeScreen(0.4)
        let brightness = GlowBrightness()
        let glow = UUID()
        brightness.raise(for: glow, on: screen)
        brightness.release(glow) // Control Center opened: the scene went inactive.
        #expect(screen.brightness == 0.4)
        screen.brightness = 0.7 // They turned it up.
        brightness.raise(for: glow, on: screen) // Back to the glow.
        brightness.release(glow) // The glow ended.
        #expect(screen.brightness == 0.7)
    }

    @Test func releasingWithoutRaisingChangesNothing() {
        let screen = FakeScreen(0.3)
        let brightness = GlowBrightness()
        brightness.raise(for: UUID(), on: screen)
        brightness.release(UUID())
        #expect(screen.brightness == 1)
        #expect(brightness.isRaised)
    }
}

@MainActor
struct GlowKeepAwakeTests {
    final class FakeApp: GlowIdleTimerControlling {
        var isIdleTimerDisabled: Bool
        init(_ disabled: Bool) {
            isIdleTimerDisabled = disabled
        }
    }

    @Test func keepsAwakeThenPutsItBack() {
        let app = FakeApp(false)
        let keepAwake = GlowKeepAwake(target: app)
        let glow = UUID()
        keepAwake.hold(glow)
        #expect(app.isIdleTimerDisabled)
        keepAwake.release(glow)
        #expect(!app.isIdleTimerDisabled)
    }

    @Test func neverTurnsOffSomeoneElsesKeepAwake() {
        let app = FakeApp(true)
        let keepAwake = GlowKeepAwake(target: app)
        let glow = UUID()
        keepAwake.hold(glow)
        keepAwake.release(glow)
        #expect(app.isIdleTimerDisabled)
    }

    @Test func overlappingHoldersReleaseTogether() {
        let app = FakeApp(false)
        let keepAwake = GlowKeepAwake(target: app)
        let first = UUID(), second = UUID()
        keepAwake.hold(first)
        keepAwake.hold(second)
        keepAwake.release(first)
        #expect(app.isIdleTimerDisabled)
        keepAwake.release(second)
        #expect(!app.isIdleTimerDisabled)
    }
}

/// The pulse, sampled over time, in both motion settings.
struct GlowPulseTests {
    static let samples = stride(from: 0.0, through: 12, by: 1.0 / 60).map(\.self)

    @Test(arguments: [false, true])
    func staysWithinItsBounds(reduceMotion: Bool) {
        for time in Self.samples {
            let frame = GlowPulse.frame(at: time, reduceMotion: reduceMotion)
            #expect((0.2 ... 1).contains(frame.opacity))
            #expect((0.85 ... 1).contains(frame.scale))
        }
    }

    @Test func reduceMotionNeverChangesSize() {
        for time in Self.samples {
            #expect(GlowPulse.frame(at: time, reduceMotion: true).scale == 1)
        }
    }

    @Test(arguments: [false, true])
    func repeatsEveryPeriod(reduceMotion: Bool) {
        let period = reduceMotion ? GlowPulse.reducedPeriod : GlowPulse.period
        for time in stride(from: 0.0, through: 3, by: 0.1) {
            let now = GlowPulse.frame(at: time, reduceMotion: reduceMotion)
            let later = GlowPulse.frame(at: time + period, reduceMotion: reduceMotion)
            #expect(abs(now.opacity - later.opacity) < 0.000_1)
        }
    }

    @Test(arguments: [false, true])
    func neverJumps(reduceMotion: Bool) {
        // From one 60 fps frame to the next, the bloom changes by a sliver: no flashes.
        var previous = GlowPulse.frame(at: 0, reduceMotion: reduceMotion)
        for time in Self.samples.dropFirst() {
            let frame = GlowPulse.frame(at: time, reduceMotion: reduceMotion)
            #expect(abs(frame.opacity - previous.opacity) < 0.05)
            previous = frame
        }
    }

    @Test(arguments: GlowHue.allCases, [false, true])
    func dimmestMomentIsAtLeast70PercentOfTheBrightest(_ hue: GlowHue, reduceMotion: Bool) throws {
        // At the bloom's center, where the change is biggest.
        let luminances = Self.samples.map { time in
            let frame = GlowPulse.frame(at: time, reduceMotion: reduceMotion)
            return GlowContrast.relativeLuminance(hue.rgb.mixed(with: .white, amount: GlowPulse.bloomStrength * frame.opacity))
        }
        let ratio = try #require(luminances.min()) / #require(luminances.max())
        #expect(ratio >= GlowPulse.minimumLuminanceRatio, "\(hue): \(ratio)")
    }
}
