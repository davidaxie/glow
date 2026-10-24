import AppCore
import Testing
@testable import GlowRealtime

// Placeholder test from A3. Owner: B5.
struct GlowRealtimeTests {
    @Test func liveFactoryReturnsAService() async throws {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        try await RealtimeModule.live(context).connect()
    }

    @Test func everyEventKindMatchesTheSpec() {
        #expect(RealtimeEventKind.allCases.map(\.rawValue) == [
            "match.created", "match.choice", "glow.started", "glow.ended",
            "message.created", "checkin.expiring", "deck.changed",
        ])
    }
}
