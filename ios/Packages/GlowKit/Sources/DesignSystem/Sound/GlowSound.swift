import AVFoundation
import SwiftUI

// Owner: U1 (design wave). Three tiny, warm sounds, synthesized in code (no audio files):
//
//     .glowSound(.chime, trigger: match?.id)     // a mutual tap
//     .glowSound(.swell, trigger: glowStarted)   // the glow arriving, a reveal
//     GlowSounds.shared.play(.tick)              // a sent message
//
// They follow the silent switch (the `.ambient` audio session mixes with other audio and is
// muted by the switch) and the Sound toggle in Settings (`GlowSounds.isEnabledKey`). Off is always
// fine: nothing in Glow needs a sound to be understood.

/// A sound cue.
public enum GlowSound: String, CaseIterable, Sendable {
    /// A soft two-note chime: a mutual tap.
    case chime
    /// A low, airy swell: the glow filling the screen, a reveal.
    case swell
    /// A faint tick: a message sent.
    case tick
}

/// The sounds as plain samples, so their shape can be tested without audio hardware.
public enum GlowSoundSynth {
    public static let sampleRate: Double = 44100

    /// Mono samples for `sound`, -1 to 1, starting and ending in silence.
    public static func samples(for sound: GlowSound, sampleRate: Double = sampleRate) -> [Float] {
        switch sound {
        case .chime:
            // Two bell-like notes a fifth apart (E6 then B6), each with a soft octave partial.
            mix(
                count: Int(sampleRate * 1.1),
                voices: [
                    Voice(frequency: 1318.5, amplitude: 0.16, start: 0, attack: 0.004, decay: 0.55),
                    Voice(frequency: 2637.0, amplitude: 0.03, start: 0, attack: 0.004, decay: 0.25),
                    Voice(frequency: 1975.5, amplitude: 0.13, start: 0.11, attack: 0.004, decay: 0.7),
                    Voice(frequency: 3951.0, amplitude: 0.02, start: 0.11, attack: 0.004, decay: 0.3),
                ],
                sampleRate: sampleRate,
            )
        case .swell:
            // A low open fifth that breathes in and out, with a little shimmer on top.
            swell(sampleRate: sampleRate)
        case .tick:
            mix(
                count: Int(sampleRate * 0.08),
                voices: [Voice(frequency: 2400, amplitude: 0.07, start: 0, attack: 0.001, decay: 0.018)],
                sampleRate: sampleRate,
            )
        }
    }

    struct Voice {
        let frequency: Double
        let amplitude: Double
        let start: Double
        let attack: Double
        let decay: Double
    }

    /// Sine voices with a fast linear attack and an exponential decay.
    static func mix(count: Int, voices: [Voice], sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for voice in voices {
            let first = Int(voice.start * sampleRate)
            guard first < count else { continue }
            for index in first ..< count {
                let time = Double(index - first) / sampleRate
                let envelope = time < voice.attack ? time / voice.attack : exp(-(time - voice.attack) / voice.decay)
                out[index] += Float(voice.amplitude * envelope * sin(2 * .pi * voice.frequency * time))
            }
        }
        return fadeOut(out, sampleRate: sampleRate)
    }

    static func swell(sampleRate: Double) -> [Float] {
        let duration = 1.8
        let count = Int(sampleRate * duration)
        var out = [Float](repeating: 0, count: count)
        let partials: [(Double, Double)] = [(196.0, 0.09), (293.7, 0.06), (392.0, 0.035), (587.3, 0.015)]
        for index in 0 ..< count {
            let time = Double(index) / sampleRate
            // A raised-cosine breath: 0 → 1 → 0 over the whole sound, peaking a little early.
            let phase = min(time / duration, 1)
            let envelope = pow(sin(.pi * pow(phase, 0.8)), 2)
            var value = 0.0
            for (frequency, amplitude) in partials {
                value += amplitude * sin(2 * .pi * frequency * time + 0.3 * sin(2 * .pi * 0.5 * time))
            }
            out[index] = Float(value * envelope)
        }
        return fadeOut(out, sampleRate: sampleRate)
    }

    /// The last 20 ms ramp to silence, so nothing ever clicks.
    static func fadeOut(_ samples: [Float], sampleRate: Double) -> [Float] {
        var samples = samples
        let ramp = min(Int(sampleRate * 0.02), samples.count)
        for offset in 0 ..< ramp {
            samples[samples.count - 1 - offset] *= Float(offset) / Float(ramp)
        }
        return samples
    }
}

/// Plays the cues. Quietly does nothing if the engine can't start or the person turned sounds off.
@MainActor
public final class GlowSounds {
    public static let shared = GlowSounds()

    /// The `UserDefaults` key behind Settings' Sound toggle. On unless turned off.
    public static let isEnabledKey = "glow.sounds.enabled"

    /// Whether sounds are on (Settings > Sound).
    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
    }

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [GlowSound: AVAudioPCMBuffer] = [:]

    public init() {}

    public func play(_ sound: GlowSound) {
        guard Self.isEnabled else { return }
        do {
            let (engine, player) = try running()
            guard engine.isRunning, let buffer = buffer(for: sound) else { return }
            player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            if !player.isPlaying {
                player.play()
            }
        } catch {
            // A sound that doesn't play is never worth surfacing; start over next time.
            engine = nil
            player = nil
        }
    }

    private func running() throws -> (AVAudioEngine, AVAudioPlayerNode) {
        if let engine, let player, engine.isRunning {
            return (engine, player)
        }
        // Ambient: mixes with other audio and respects the silent switch.
        try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: GlowSoundSynth.sampleRate, channels: 1)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine
        self.player = player
        return (engine, player)
    }

    private func buffer(for sound: GlowSound) -> AVAudioPCMBuffer? {
        if let buffer = buffers[sound] {
            return buffer
        }
        let samples = GlowSoundSynth.samples(for: sound)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: GlowSoundSynth.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        buffers[sound] = buffer
        return buffer
    }
}

extension View {
    /// Plays `sound` each time `trigger` changes (when sounds are on and the ringer isn't silent).
    public func glowSound(_ sound: GlowSound, trigger: some Equatable) -> some View {
        onChange(of: trigger) { GlowSounds.shared.play(sound) }
    }
}
