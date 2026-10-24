import AppCore
import SwiftUI

// Placeholders from A3 so the module graph compiles on day one. Owner: B1.
// Keep these views public with these initializers: the app shows them for `.settings`,
// `.editProfile` and `.editPhotos`. Replace everything inside them.

/// The Settings tab.
public struct SettingsView: View {
    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies

    public init() {}

    public var body: some View {
        List {
            Section {
                Button("Edit profile") { navigate(.editProfile) }
                Button("Edit photos") { navigate(.editPhotos) }
            }
            Section {
                Button("Pause") { navigate(.pause) }
                Button("Delete account", role: .destructive) { navigate(.deleteAccount) }
            }
            if dependencies.config.environment == .debug {
                Section("Debug") {
                    Button("Gallery") { navigate(.gallery) }
                }
            }
        }
        .accessibilityIdentifier("screen.FeatureSettings")
        .navigationTitle("Settings")
    }
}

public struct EditProfileView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Edit profile", module: "FeatureSettings", owner: "B1")
    }
}

public struct EditPhotosView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Edit photos", module: "FeatureSettings", owner: "B1")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
