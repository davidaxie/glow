import AppCore
import Testing
@testable import Glow

/// Tests for the app target itself, hosted in the Debug app.
struct AppTargetTests {
    @Test func debugConfigComesFromTheXcconfig() {
        let config = AppComposition.loadConfig()
        #expect(config.environment == .debug)
        #expect(config.apiBaseURL.absoluteString == "http://localhost:3000")
        #expect(config.supabaseURL?.absoluteString == "http://127.0.0.1:54421")
        #expect(config.allowsCustomScheme)
        #expect(!config.webDomain.isEmpty)
    }

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
