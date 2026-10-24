import AppCore
import Testing
@testable import Location

// Placeholder test from A3. Owner: B2.
struct LocationTests {
    @Test func liveFactoryReturnsAService() async {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        let location = LocationModule.live(context)
        #expect(await location.authorization() == .precise)
    }
}
