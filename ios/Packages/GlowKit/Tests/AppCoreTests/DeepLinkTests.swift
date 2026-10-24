import Foundation
import Testing
@testable import AppCore

struct DeepLinkTests {
    let debug = AppConfig.preview
    var release: AppConfig {
        var config = AppConfig.preview
        config.environment = .release
        config.allowsCustomScheme = false
        return config
    }

    @Test func universalLinkOpensTheRoom() throws {
        let url = try #require(URL(string: "https://glow.example/r/demo?t=ABCD2345"))
        #expect(DeepLink.route(for: url, config: debug) == .joinRoom(RoomLink(slug: "demo", token: "ABCD2345")))
    }

    @Test func universalLinkWorksInRelease() throws {
        let url = try #require(URL(string: "https://GLOW.example/r/Demo?t=ABCD2345"))
        #expect(DeepLink.route(for: url, config: release) == .joinRoom(RoomLink(slug: "demo", token: "ABCD2345")))
    }

    @Test func customSchemeWorksInDebugOnly() throws {
        let url = try #require(URL(string: "glow://r/demo?t=ABCD2345"))
        #expect(DeepLink.route(for: url, config: debug) == .joinRoom(RoomLink(slug: "demo", token: "ABCD2345")))
        #expect(DeepLink.route(for: url, config: release) == nil)
    }

    @Test func linkWithoutTokenStillOpensTheRoom() throws {
        let url = try #require(URL(string: "https://glow.example/r/demo"))
        #expect(DeepLink.route(for: url, config: debug) == .joinRoom(RoomLink(slug: "demo", token: nil)))
    }

    @Test func malformedTokenIsDropped() throws {
        let url = try #require(URL(string: "https://glow.example/r/demo?t=%3Cscript%3E"))
        #expect(DeepLink.route(for: url, config: debug) == .joinRoom(RoomLink(slug: "demo", token: nil)))
    }

    @Test(arguments: [
        "https://evil.example/r/demo?t=ABCD2345", // another host
        "http://glow.example/r/demo?t=ABCD2345", // not https
        "https://glow.example:8443/r/demo", // another port
        "https://glow.example/x/demo", // not a room path
        "https://glow.example/r/demo/extra", // too deep
        "https://glow.example/r/-demo", // bad slug
        "https://glow.example/r/de_mo", // bad slug
        "glow://match/00000000-0000-4000-8000-000000000001", // not a room link
        "mailto:someone@example.com",
    ])
    func otherLinksAreIgnored(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(DeepLink.route(for: url, config: debug) == nil)
    }
}
