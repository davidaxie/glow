import Testing
@testable import DesignSystem

/// U1's haptics and sound choreography (docs/design/DIRECTION.md, "Haptics and sound").
struct ChoreographyTests {
    @Test func theHeartbeatIsTwoSoftBeats120msApart() {
        let beats = GlowHapticPattern.heartbeatPair.events
        #expect(beats.count == 2)
        #expect(beats[1].time - beats[0].time == 0.12)
        #expect(beats.allSatisfy { $0.sharpness <= 0.3 && $0.duration == nil })
        #expect(beats[1].intensity < beats[0].intensity)
    }

    @Test func momentsPairTheRightHapticAndSound() {
        #expect(GlowMoment.mutual.haptic == .heartbeat)
        #expect(GlowMoment.mutual.sound == .chime)
        #expect(GlowMoment.reveal.haptic == .reveal)
        #expect(GlowMoment.reveal.sound == .swell)
        #expect(GlowMoment.glowArrives.sound == .swell)
        #expect(GlowMoment.messageSent.sound == .tick)
        #expect(GlowMoment.cardLeaves.sound == nil)
    }

    @Test(arguments: GlowSound.allCases)
    func soundsAreQuietShortAndClickFree(_ sound: GlowSound) {
        let samples = GlowSoundSynth.samples(for: sound)
        let seconds = Double(samples.count) / GlowSoundSynth.sampleRate
        #expect(seconds > 0.02 && seconds <= 2, "\(sound) lasts \(seconds) s")
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.01, "\(sound) is silent")
        #expect(peak < 0.5, "\(sound) peaks at \(peak): these are tiny, warm sounds")
        #expect(abs(samples.first ?? 1) < 0.01)
        #expect(abs(samples.last ?? 1) < 0.001)
    }

    @Test func theTickIsTheFaintest() {
        func peak(_ sound: GlowSound) -> Float {
            GlowSoundSynth.samples(for: sound).map(abs).max() ?? 0
        }
        #expect(peak(.tick) < peak(.chime))
        #expect(peak(.tick) < peak(.swell))
    }
}
