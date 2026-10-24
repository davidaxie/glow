import Foundation
import Testing
@testable import LiveActivityShared

// Placeholder test from A3. Owner: C3.
struct LiveActivitySharedTests {
    @Test func contentStateRoundTrips() throws {
        let state = GlowActivityAttributes.ContentState(endsAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(
            GlowActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state),
        )
        #expect(decoded == state)
    }
}
