import Foundation
import Testing
@testable import AppCore

@MainActor
struct RouterTests {
    let match = MatchID(rawValue: "00000000-0000-4000-8000-000000000001")
    let room = RoomID(rawValue: "00000000-0000-4000-8000-000000000002")
    let demoLink = URL(string: "glow://r/demo?t=ABCD2345")!

    func readyRouter() -> Router {
        let router = Router(config: .preview)
        router.apply(.ready)
        return router
    }

    @Test func startsLaunchingThenFollowsTheSession() {
        let router = Router(config: .preview)
        #expect(router.phase == .launching)
        router.apply(.signedOut)
        #expect(router.phase == .onboarding(.welcome))
        router.apply(.onboarding(.photos))
        #expect(router.phase == .onboarding(.photos))
        router.apply(.ready)
        #expect(router.phase == .main)
    }

    @Test func pushRoutesLandOnTheirTab() {
        let router = readyRouter()
        router.go(.chat(match))
        #expect(router.selectedTab == .matches)
        #expect(router.matchesPath == [.chat(match)])
        router.go(.chat(match))
        #expect(router.matchesPath == [.chat(match)], "the same route twice doesn't stack")
        router.go(.roomHome(room))
        #expect(router.selectedTab == .rooms)
        #expect(router.roomsPath == [.roomHome(room)])
    }

    @Test func tabRootsPopToRoot() {
        let router = readyRouter()
        router.go(.editProfile)
        router.go(.settings)
        #expect(router.selectedTab == .settings)
        #expect(router.settingsPath.isEmpty)
    }

    @Test func takeoversAndSheets() {
        let router = readyRouter()
        router.go(.report(.chat(match)))
        #expect(router.sheet == .report(.chat(match)))
        router.go(.mutual(match))
        #expect(router.cover == .mutual(match))
        #expect(router.sheet == nil)
        router.go(.glow(match))
        #expect(router.cover == .glow(match), "glow replaces the mutual takeover")
        router.go(.chat(match))
        #expect(router.cover == nil, "pushing a screen closes the takeover")
        #expect(router.matchesPath == [.chat(match)])
    }

    @Test func linksResetTheRoomsStack() {
        let router = readyRouter()
        router.go(.deck(room))
        router.go(.mutual(match))
        #expect(router.open(demoLink))
        #expect(router.cover == nil)
        #expect(router.selectedTab == .rooms)
        #expect(router.roomsPath == [.joinRoom(RoomLink(slug: "demo", token: "ABCD2345"))])
    }

    @Test func linksBeforeOnboardingWaitUntilItsDone() {
        let router = Router(config: .preview)
        router.apply(.onboarding(.profile))
        #expect(router.open(demoLink))
        #expect(router.roomsPath.isEmpty, "rooms can't open until onboarding is finished")
        #expect(router.pendingRoute == .joinRoom(RoomLink(slug: "demo", token: "ABCD2345")))
        router.apply(.ready)
        #expect(router.pendingRoute == nil)
        #expect(router.roomsPath == [.joinRoom(RoomLink(slug: "demo", token: "ABCD2345"))])
    }

    @Test func routesBeforeOnboardingWait() {
        let router = Router(config: .preview)
        router.apply(.signedOut)
        router.go(.chat(match))
        #expect(router.matchesPath.isEmpty)
        #expect(router.pendingRoute == .chat(match))
    }

    @Test func signingOutForgetsEverything() {
        let router = readyRouter()
        router.go(.chat(match))
        router.go(.report(.chat(match)))
        router.apply(.signedOut)
        #expect(router.matchesPath.isEmpty)
        #expect(router.sheet == nil)
        #expect(router.pendingRoute == nil)
        #expect(router.phase == .onboarding(.welcome))
    }

    @Test func foreignLinksAreIgnored() throws {
        let router = readyRouter()
        #expect(try router.open(#require(URL(string: "https://evil.example/r/demo"))) == false)
        #expect(router.roomsPath.isEmpty)
    }

    @Test func galleryIsDebugOnly() {
        var config = AppConfig.preview
        config.environment = .release
        let router = Router(config: config)
        router.apply(.ready)
        router.go(.gallery)
        #expect(router.settingsPath.isEmpty)
    }

    @Test func linksAreCountedWithoutDetails() {
        let analytics = RecordingAnalytics()
        let router = Router(config: .preview, analytics: analytics)
        router.apply(.ready)
        router.open(demoLink)
        #expect(analytics.events == [AnalyticsEvent("deep_link_opened", ["route": "join_room"])])
    }
}
