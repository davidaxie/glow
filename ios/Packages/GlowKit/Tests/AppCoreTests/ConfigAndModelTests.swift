import Foundation
import Testing
@testable import AppCore

struct ConfigTests {
    let info: [String: Any] = [
        AppConfig.InfoKey.apiBaseURL: "https://glow.example",
        AppConfig.InfoKey.supabaseURL: "https://project.supabase.co",
        AppConfig.InfoKey.supabaseAnonKey: "anon",
        AppConfig.InfoKey.webDomain: "Glow.Example",
        AppConfig.InfoKey.posthogKey: "",
        AppConfig.InfoKey.sentryDSN: "",
    ]

    @Test func readsInfoPlist() throws {
        let config = try AppConfig(infoDictionary: info, environment: .release, allowsCustomScheme: false)
        #expect(config.apiBaseURL == URL(string: "https://glow.example"))
        #expect(config.webDomain == "glow.example")
        #expect(config.supabaseAnonKey == "anon")
        #expect(config.posthogKey.isEmpty)
        #expect(config.posthogHost == nil)
    }

    @Test func releaseRequiresHTTPS() {
        var info = info
        info[AppConfig.InfoKey.apiBaseURL] = "http://glow.example"
        #expect(throws: AppConfigError.insecureAPIURL) {
            try AppConfig(infoDictionary: info, environment: .release, allowsCustomScheme: false)
        }
    }

    @Test func missingKeysFailClearly() {
        #expect(throws: AppConfigError.missing(key: AppConfig.InfoKey.apiBaseURL)) {
            try AppConfig(infoDictionary: [:], environment: .debug, allowsCustomScheme: true)
        }
    }
}

struct ModelTests {
    @Test func identifiersValidateUUIDs() {
        #expect(MatchID(validating: "not-a-uuid") == nil)
        let id = MatchID(validating: "0000000A-0000-4000-8000-000000000001")
        #expect(id?.rawValue == "0000000a-0000-4000-8000-000000000001")
    }

    @Test func identifiersCodeAsPlainStrings() throws {
        let id = RoomID(rawValue: "00000000-0000-4000-8000-000000000002")
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == #"["00000000-0000-4000-8000-000000000002"]"#)
        #expect(try JSONDecoder().decode([RoomID].self, from: data) == [id])
    }

    @Test func everyRouteHasAPresentation() {
        let match = MatchID(rawValue: "00000000-0000-4000-8000-000000000001")
        #expect(Route.mutual(match).presentation == .fullScreen)
        #expect(Route.block(.card(CardID(rawValue: "x"))).presentation == .sheet)
        #expect(Route.joinRoom(RoomLink(slug: "demo", token: nil)).presentation == .push(.rooms))
        #expect(Route.onboarding(.welcome).requiresOnboarding == false)
        #expect(Route.rooms.requiresOnboarding)
    }

    @Test func broadcasterStartsWithTheCurrentValue() async {
        let session = PreviewSessionService(state: .onboarding(.profile))
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .onboarding(.profile))
        session.set(.ready)
        #expect(await states.next() == .ready)
    }
}
