import Foundation
import SwiftUI
import Testing
@testable import DesignSystem

/// The tokens match docs/SPEC.md and the contract, so B7's CSS and the API agree with the app.
struct TokenTests {
    @Test func colorTokensMatchTheSpec() {
        let spec: [String: String] = [
            "background": "#0B0B10", "surface": "#16161D", "surfaceRaised": "#20202A", "textPrimary": "#F4F4F6",
            "textSecondary": "#A1A1AA", "line": "#2A2A35", "accent": "#FF4FA3", "danger": "#FF5A5F",
        ]
        #expect(Dictionary(uniqueKeysWithValues: GlowPalette.tokens.map { ($0.name, $0.rgb.hex) }) == spec)
    }

    @Test func glowColorsMatchTheSpec() {
        let spec: [GlowHue: String] = [
            .ember: "#FF6B2C", .rose: "#FF3D8B", .violet: "#8C5BFF", .sky: "#2F8CFF",
            .aqua: "#12D6C5", .lime: "#9BE52E", .sun: "#FFD23F", .pearl: "#F2F2F7",
        ]
        for hue in GlowHue.allCases {
            #expect(hue.rgb.hex == spec[hue])
        }
    }

    @Test func glowColorNamesMatchTheContract() throws {
        #expect(try ContractFile.enumValues(of: "GlowColor") == GlowHue.allCases.map(\.rawValue))
    }

    @Test func everyTagColorInTheContractHasASwatch() throws {
        let swatches = Set(GlowSwatch.allCases.map(\.rawValue))
        for schema in ["TopColor", "HairColor"] {
            for value in try ContractFile.enumValues(of: schema) {
                #expect(swatches.contains(value), "\(schema).\(value) has no GlowSwatch")
            }
        }
    }

    @Test func spacingIsOnTheFourPointGrid() {
        for step in GlowSpacing.scale {
            #expect(step.value.truncatingRemainder(dividingBy: GlowSpacing.unit) == 0, "\(step.name)")
        }
        #expect(GlowSpacing.screenMargin.truncatingRemainder(dividingBy: GlowSpacing.unit) == 0)
        #expect(GlowSpacing.grid(5) == 20)
    }

    @Test func cornersMatchTheSpec() {
        #expect(GlowRadius.control == 12)
        #expect(GlowRadius.card == 20)
    }

    @Test func uiMotionIsAFifthOfASecond() {
        #expect(GlowMotion.uiDuration == 0.2)
    }

    @Test func mixingMovesTowardTheOtherColor() {
        #expect(GlowRGB.black.mixed(with: .white, amount: 0.5).hex == "#808080")
        #expect(GlowPalette.accent.mixed(with: .white, amount: 0) == GlowPalette.accent)
        #expect(GlowPalette.accent.mixed(with: .white, amount: 2) == .white)
    }

    @Test func toastsStayLongerForVoiceOver() {
        let toast = GlowToastMessage("Saved", duration: .seconds(3))
        #expect(toast.displayDuration(voiceOverEnabled: false) == .seconds(3))
        #expect(toast.displayDuration(voiceOverEnabled: true) == .seconds(6))
        #expect(GlowToastMessage("Saved", duration: .seconds(5)).displayDuration(voiceOverEnabled: true) == .seconds(10))
    }
}

/// Reads enum values out of contracts/openapi.yaml, so a renamed contract value fails here.
enum ContractFile {
    static var repoRoot: URL {
        // Tests/DesignSystemTests/TokenTests.swift → the repository root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 {
            url.deleteLastPathComponent()
        }
        return url
    }

    static func enumValues(of schema: String) throws -> [String] {
        let yaml = try String(contentsOf: repoRoot.appending(path: "contracts/openapi.yaml"), encoding: .utf8)
        let lines = yaml.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "    \(schema):") else {
            throw ContractError.missing(schema)
        }
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("enum: [") {
                return trimmed.dropFirst("enum: [".count).dropLast()
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            // The next schema starts at the same indent: this one has no inline enum.
            if line.hasPrefix("    "), !line.hasPrefix("     ") {
                break
            }
        }
        throw ContractError.missing(schema)
    }

    enum ContractError: Error {
        case missing(String)
    }
}
