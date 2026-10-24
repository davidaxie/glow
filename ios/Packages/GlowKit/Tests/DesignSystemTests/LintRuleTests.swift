import Foundation
import Testing

/// The SwiftLint rules in .swiftlint.yml that stop feature modules defining their own colors or
/// fonts (B6 brief) catch what they should and leave the DesignSystem way alone. SwiftLint uses
/// NSRegularExpression too, so these are the same matches CI makes (minus comments and strings,
/// which the rules skip).
struct LintRuleTests {
    @Test(arguments: [
        "Text(\"a\").foregroundStyle(Color(red: 1, green: 0, blue: 0))",
        "Text(\"a\").foregroundStyle(Color.red)",
        "Text(\"a\").foregroundStyle(.white)",
        "Text(\"a\").background(.black)",
        "Text(\"a\").foregroundStyle(Color(\"Brand\"))",
        "Text(\"a\").shadow(color: .black, radius: 2)",
        "Text(\"a\").tint(.secondary)",
        "let color = UIColor(white: 1, alpha: 1)",
        "let color = UIColor.systemPink",
        "let color = #colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)",
        "let color = CGColor(gray: 0.5, alpha: 1)",
        "let color = Color.init(white: 0.5)",
    ])
    func colorRuleCatches(_ line: String) throws {
        #expect(try LintRules.matches("glow_feature_colors", line))
    }

    @Test(arguments: [
        "Text(\"a\").font(.system(size: 20))",
        "Text(\"a\").font(.title)",
        "Text(\"a\").font(.body.weight(.bold))",
        "Text(\"a\").font(Font.custom(\"Avenir\", size: 14))",
        "Text(\"a\").font(Font.body)",
        "Text(\"a\").fontDesign(.rounded)",
        "let font = UIFont.preferredFont(forTextStyle: .body)",
    ])
    func fontRuleCatches(_ line: String) throws {
        #expect(try LintRules.matches("glow_feature_fonts", line))
    }

    @Test(arguments: [
        "Text(\"a\").glowFont(.body).foregroundStyle(.glowTextSecondary)",
        "Text(\"a\").font(.glow(.headline)).background(.glowSurface).tint(.glowAccent)",
        "Text(\"a\").foregroundStyle(Color.glowAccent)",
        "Text(\"a\").foregroundStyle(GlowSwatch.red.rgb.color)",
        "Rectangle().fill(.glowClear).fill(Color.clear)",
        "let hue = GlowHue(rawValue: session.color.rawValue)",
        "let top = TopColor(rawValue: \"red\")",
        "let picks: [TopColor] = [.green, .blue, .black]",
        "case .red, .white: return true",
        "filters.topColor = [.red]",
        "Text(\"a\").font(GlowTextStyle.body.font)",
        "Text(\"a\").bold()",
    ])
    func designSystemCodePasses(_ line: String) throws {
        #expect(try !LintRules.matches("glow_feature_colors", line))
        #expect(try !LintRules.matches("glow_feature_fonts", line))
    }

    @Test func rulesOnlyApplyToFeatureModules() throws {
        for rule in ["glow_feature_colors", "glow_feature_fonts"] {
            let included = try LintRules.value("included", of: rule)
            let pattern = try NSRegularExpression(pattern: included)
            func applies(_ path: String) -> Bool {
                pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
            }
            #expect(applies("/repo/ios/Packages/GlowKit/Sources/FeatureDeck/DeckView.swift"))
            #expect(applies("/repo/ios/Packages/GlowKit/Sources/FeatureGlow/Sub/GlowView.swift"))
            #expect(!applies("/repo/ios/Packages/GlowKit/Sources/DesignSystem/Tokens/GlowPalette.swift"))
            #expect(!applies("/repo/ios/Packages/GlowKit/Tests/FeatureDeckTests/DeckTests.swift"))
            #expect(!applies("/repo/ios/Packages/GlowKit/Sources/AppCore/Support/PlaceholderScreen.swift"))
        }
    }
}

/// Reads custom rules out of the repository's .swiftlint.yml.
enum LintRules {
    static var config: String {
        get throws {
            var url = URL(fileURLWithPath: #filePath)
            for _ in 0 ..< 6 {
                url.deleteLastPathComponent()
            }
            return try String(contentsOf: url.appending(path: ".swiftlint.yml"), encoding: .utf8)
        }
    }

    /// A single-quoted value of `key` under the custom rule `rule`.
    static func value(_ key: String, of rule: String) throws -> String {
        let lines = try config.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "  \(rule):") else { throw Missing.rule(rule) }
        for line in lines[(start + 1)...] {
            if line.hasPrefix("  "), !line.hasPrefix("   ") {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key): '"), trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst(key.count + 3).dropLast()).replacingOccurrences(of: "''", with: "'")
            }
        }
        throw Missing.key(key, rule)
    }

    static func matches(_ rule: String, _ line: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: value("regex", of: rule))
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    enum Missing: Error {
        case rule(String)
        case key(String, String)
    }
}
