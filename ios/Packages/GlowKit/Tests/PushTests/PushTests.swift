import AppCore
import Foundation
import Testing
@testable import Push

// Placeholder test from A3. Owner: B5.
struct PushTests {
    @Test func liveFactoryReturnsAService() async {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        let push = PushModule.live(context)
        #expect(await push.authorization() == .authorized)
        #expect(push.route(for: PushNotification(categoryIdentifier: "", payload: Data("{}".utf8))) == nil)
    }
}
