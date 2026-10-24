import AppCore
import Testing
@testable import Session

// Placeholder test from A3. Owner: B1.
struct SessionTests {
    @Test func liveFactoryReturnsASession() async {
        let session = SessionModule.live(config: .preview, analytics: NoopAnalytics())
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() != nil)
    }
}
