import Foundation
import Testing

// Owner: C4 (CHIPS-D1). Icebreaker chips exist only on screens that come after a mutual match and
// a choice: the glow screen (FeatureGlow) and an open chat (FeatureChat). These source-level checks
// fail if a chip type or a chip's words ever show up anywhere that can be reached before a match.
//
// Feature modules can't import each other (AGENTS.md), so a chip can only get into another screen
// by being copied there. The checks look for the types and for the words.

struct IcebreakerReachabilityTests {
    /// ios/Packages/GlowKit, found from this file's path.
    static let kit: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    /// Every module that is on screen before a match, or that supports those screens. Chips live
    /// in FeatureGlow and FeatureChat only.
    static let otherModules = [
        "FeatureDeck", "FeatureRooms", "FeatureCheckIn", "FeatureMatch", "FeatureOnboarding", "FeatureSettings",
        "FeatureSafety", "AppCore", "DesignSystem", "Session", "Location", "Imaging", "Push", "GlowRealtime",
    ]

    /// Type names and the screens' words. Any of them in another module is a chip leaking out.
    static let tokens = [
        "ChatIcebreaker", "GlowSayAloud", "Icebreaker",
        "Need an excuse", "Need a way to start", "Suggested opener",
        "We both noticed", "brought you to", "I'm the other one", "Shall we sit by", "find a seat at",
    ]

    static func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test(arguments: otherModules)
    func noOtherModuleHasAChipOrItsWords(module: String) throws {
        let files = Self.swiftFiles(under: Self.kit.appending(path: "Sources/\(module)"))
        #expect(!files.isEmpty, "\(module) has no sources to check, so the path is wrong")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in Self.tokens {
                #expect(!source.contains(token), "\(module)/\(file.lastPathComponent) mentions \(token)")
            }
        }
    }

    @Test func onlyTheGlowAndChatModulesHaveChips() throws {
        // Positive control: the check does find them where they belong.
        let chat = try String(contentsOf: Self.kit.appending(path: "Sources/FeatureChat/ChatIcebreaker.swift"), encoding: .utf8)
        let glow = try String(contentsOf: Self.kit.appending(path: "Sources/FeatureGlow/GlowSayAloud.swift"), encoding: .utf8)
        #expect(chat.contains("Suggested opener") && chat.contains("ChatIcebreaker"))
        #expect(glow.contains("Need an excuse") && glow.contains("GlowSayAloud"))
    }

    @Test func noPreMatchModuleCanImportFeatureGlowOrFeatureChat() throws {
        let manifest = try String(contentsOf: Self.kit.appending(path: "Package.swift"), encoding: .utf8)
        let moduleLines = manifest.split(separator: "\n").filter { $0.contains("Module(name:") }
        for module in Self.otherModules where module.hasPrefix("Feature") {
            let line = try #require(moduleLines.first { $0.contains("name: \"\(module)\"") }, "\(module) not in Package.swift")
            #expect(!line.contains("FeatureGlow") && !line.contains("FeatureChat"), "\(module) depends on a chip module")
        }
    }

    @Test func theAppShowsTheGlowAndChatScreensOnlyForTheirRoutes() throws {
        // GlowView and ChatView are built in one place, for the .glow and .chat routes. The server
        // adds a second lock: chat answers 409 while choosing and the glow answers 404 until it
        // starts, so even an early route shows "not open" or "gone", with no chips.
        let app = Self.kit.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Glow")
        let files = Self.swiftFiles(under: app)
        #expect(!files.isEmpty)
        for file in files where file.lastPathComponent != "RouteDestination.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("GlowView(") && !source.contains("ChatView("), "\(file.lastPathComponent) shows a chip screen")
        }
        let routes = try String(contentsOf: app.appending(path: "Navigation/RouteDestination.swift"), encoding: .utf8)
        #expect(routes.contains("case let .glow(match): GlowView(matchID: match)"))
        #expect(routes.contains("case let .chat(match): ChatView(matchID: match)"))
    }
}
