import AppCore
import Foundation
import Testing
@testable import Glow

/// Tests for the app target itself, hosted in the Debug app.
struct AppTargetTests {
    /// The URLs come from the build: `localhost:3000` and the shared Supabase by default, or an
    /// agent's own port and stack when `scripts/agent-env.sh` overrides them (AGENTS.md). So check
    /// that the config matches what this build put in Info.plist, and that Debug stays local.
    @Test func debugConfigComesFromTheBuild() throws {
        let config = AppComposition.loadConfig()
        #expect(config.environment == .debug)

        let builtAPI = try #require(Bundle.main.object(forInfoDictionaryKey: "GlowAPIBaseURL") as? String)
        #expect(config.apiBaseURL.absoluteString == builtAPI)
        #expect(config.apiBaseURL.scheme == "http")
        #expect(Self.localHosts.contains(config.apiBaseURL.host() ?? ""))

        let builtSupabase = try #require(Bundle.main.object(forInfoDictionaryKey: "GlowSupabaseURL") as? String)
        #expect(config.supabaseURL?.absoluteString == builtSupabase)
        #expect(Self.localHosts.contains(config.supabaseURL?.host() ?? ""))

        #expect(config.allowsCustomScheme)
        #expect(!config.webDomain.isEmpty)
    }

    private static let localHosts: Set = ["localhost", "127.0.0.1"]

    @Test func debugBuildRegistersTheGlowScheme() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == ["glow"])
    }

    @Test func analyticsIsANoopWithoutKeys() {
        var config = AppConfig.preview
        config.posthogKey = ""
        config.sentryDSN = ""
        #expect(LiveAnalytics.make(config: config) is NoopAnalytics)
    }

    @Test func purposeStringsArePresent() {
        for key in ["NSCameraUsageDescription", "NSPhotoLibraryUsageDescription", "NSLocationWhenInUseUsageDescription"] {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
            #expect(value?.isEmpty == false, "\(key) is missing")
        }
    }
}
