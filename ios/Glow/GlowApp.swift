import AppCore
import SwiftUI

@main
struct GlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(router: appDelegate.router)
                .environment(\.dependencies, appDelegate.dependencies)
        }
    }
}
