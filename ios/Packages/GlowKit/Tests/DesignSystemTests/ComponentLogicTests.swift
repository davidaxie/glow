import SwiftUI
import Testing
@testable import DesignSystem

struct CodeFormatTests {
    @Test func roomCodesKeepOnlyTheAlphabetUppercased() {
        #expect(GlowCodeFormat.roomCode.sanitize("hack26", length: 6) == "HACK26")
        #expect(GlowCodeFormat.roomCode.sanitize("hk-2 6x", length: 6) == "HK26X")
        // No I, O, 0 or 1: they're too easy to confuse.
        #expect(GlowCodeFormat.roomCode.sanitize("IO01AB", length: 6) == "AB")
        #expect(GlowCodeFormat.roomCode.sanitize("ABCDEFGH", length: 6) == "ABCDEF")
    }

    @Test func emailCodesKeepOnlyDigits() {
        #expect(GlowCodeFormat.digits.sanitize("12 34-56", length: 6) == "123456")
        #expect(GlowCodeFormat.digits.sanitize("١٢٣abc4", length: 6) == "4")
        #expect(GlowCodeFormat.digits.sanitize("1234567", length: 6) == "123456")
    }

    @Test func theAlphabetMatchesTheContract() throws {
        // contracts/constants.json: "6 characters from ABCDEFGHJKLMNPQRSTUVWXYZ23456789".
        let constants = try String(contentsOf: ContractFile.repoRoot.appending(path: "contracts/constants.json"), encoding: .utf8)
        #expect(constants.contains(GlowCodeFormat.roomCodeAlphabet))
    }
}

struct HapticPatternTests {
    @Test func theMutualMomentRisesThenSwells() {
        let taps = GlowHapticPattern.mutual.events.filter { $0.duration == nil }
        #expect(taps.count == 3)
        #expect(zip(taps, taps.dropFirst()).allSatisfy { $0.intensity < $1.intensity })
        #expect(GlowHapticPattern.mutual.events.last?.duration != nil)
        #expect(GlowHapticPattern.mutual.duration < 1)
    }

    @Test func theGlowPulseBeatsInTimeWithTheGlow() {
        let pattern = GlowHapticPattern.heartbeat(beats: 3)
        let firstOfEachBeat = pattern.events.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element.time)
        #expect(firstOfEachBeat == [0, GlowPulse.period, 2 * GlowPulse.period])
        #expect(pattern.events.allSatisfy { $0.sharpness <= 0.2 }) // soft, never crisp
    }

    @Test(arguments: [GlowHapticPattern.mutual, .glowPulse])
    func everyValueIsInRange(_ pattern: GlowHapticPattern) throws {
        for event in pattern.events {
            #expect((0 ... 1).contains(event.intensity))
            #expect((0 ... 1).contains(event.sharpness))
        }
        _ = try pattern.makePattern()
    }
}

@MainActor
struct TagPickerTests {
    enum Extra: String, CaseIterable { case glasses, hat, beard }

    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) {
            self.value = value
        }

        var binding: Binding<Value> {
            Binding { self.value } set: { self.value = $0 }
        }
    }

    @Test func pickingSeveralStopsAtTheLimit() {
        let box = Box<Set<Extra>>([])
        let picker = GlowTagPicker(options: Extra.allCases, selection: box.binding, limit: 2) { GlowTag($0.rawValue) }
        picker.toggle(.glasses)
        picker.toggle(.hat)
        #expect(!picker.isAvailable(.beard))
        picker.toggle(.beard)
        #expect(box.value == [.glasses, .hat])
        picker.toggle(.hat)
        #expect(picker.isAvailable(.beard))
    }

    @Test func pickingOneReplacesTheLast() {
        let box = Box<Extra?>(nil)
        let picker = GlowTagPicker(options: Extra.allCases, selection: box.binding) { GlowTag($0.rawValue) }
        picker.toggle(.glasses)
        picker.toggle(.hat)
        #expect(box.value == .hat)
        picker.toggle(.hat) // A required pick stays picked.
        #expect(box.value == .hat)
    }

    @Test func anOptionalPickCanBeCleared() {
        let box = Box<Extra?>(.beard)
        let picker = GlowTagPicker(options: Extra.allCases, selection: box.binding, allowsNone: true) { GlowTag($0.rawValue) }
        picker.toggle(.beard)
        #expect(box.value == nil)
    }
}
