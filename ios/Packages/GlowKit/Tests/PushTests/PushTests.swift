import AppCore
import Foundation
import Testing
import UserNotifications
@testable import Push

struct PushTests {
    @Test func categoriesComeFromTheContract() {
        #expect(PushCategories.identifiers == ["MATCH", "GLOW", "MESSAGE", "CHECKIN"])
        #expect(Set(PushCategories.all.map(\.identifier)) == Set(PushCategories.identifiers))
        // Nothing can be done from the lock screen, and hidden previews just say "Glow".
        for category in PushCategories.all {
            #expect(category.actions.isEmpty)
            #expect(category.hiddenPreviewsBodyPlaceholder == "Glow")
        }
    }

    @Test func everyPushFixtureUsesARegisteredCategory() throws {
        for name in try PushFixtures.names() {
            let aps = try #require(PushFixtures.json(name)["aps"] as? [String: Any])
            if let category = aps["category"] as? String {
                #expect(PushCategories.identifiers.contains(category), "\(name) uses \(category)")
            }
        }
    }

    @Test func appVersionFitsTheContract() {
        #expect(PushModule.appVersion(bundle: .main).map { $0.count <= 32 } ?? true)
    }
}
