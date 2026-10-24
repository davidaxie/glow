import AppCore
import Foundation
import Testing
@testable import Imaging

// Placeholder test from A3. Owner: B3.
struct ImagingTests {
    @Test func liveFactoryReturnsAService() async throws {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        let photo = try await ImagingModule.live(context).prepareCardPhoto(from: Data([1, 2, 3]))
        #expect(photo.jpegData.count == 3)
    }
}
