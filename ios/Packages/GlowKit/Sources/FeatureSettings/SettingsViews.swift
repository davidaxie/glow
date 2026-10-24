import APIClient
import AppCore
import DesignSystem
import Session
import SwiftUI

/// The Settings tab: my profile and photos, pause and delete (B8's screens), and signing out.
public struct SettingsView: View {
    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies
    @State private var me: Me?
    @State private var confirmSignOut = false
    @State private var isSigningOut = false

    public init() {}

    public var body: some View {
        List {
            Section {
                SettingsProfileSummary(me: me)
                    .listRowBackground(Color.glowSurface)
            }
            Section {
                SettingsRow("Edit profile", systemImage: "person") { navigate(.editProfile) }
                    .accessibilityIdentifier("settings.editProfile")
                SettingsRow("Edit photos", systemImage: "photo.on.rectangle") { navigate(.editPhotos) }
                    .accessibilityIdentifier("settings.editPhotos")
            } header: {
                SettingsHeader("Profile")
            }
            Section {
                SettingsRow(
                    me?.profile.paused == true ? "Paused: nobody sees you" : "Pause",
                    systemImage: "pause.circle",
                ) { navigate(.pause) }
                    .accessibilityIdentifier("settings.pause")
            } header: {
                SettingsHeader("Visibility")
            } footer: {
                SettingsFooter("While you're paused, you leave every deck at once.")
            }
            Section {
                SettingsRow("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { confirmSignOut = true }
                    .accessibilityIdentifier("settings.signOut")
                SettingsRow("Delete account", systemImage: "trash", isDanger: true) { navigate(.deleteAccount) }
                    .accessibilityIdentifier("settings.deleteAccount")
            } header: {
                SettingsHeader("Account")
            }
            if dependencies.config.environment == .debug {
                Section {
                    SettingsRow("Gallery", systemImage: "paintpalette") { navigate(.gallery) }
                } header: {
                    SettingsHeader("Debug")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.glowBackground)
        .glowLoading(isSigningOut)
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Glow?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await signOut() }
            }
            .accessibilityIdentifier("settings.signOut.confirm")
        } message: {
            Text("Your profile stays. Sign in again with the same Apple ID or email to come back.")
        }
        .accessibilityIdentifier("screen.FeatureSettings")
        .task {
            for await profile in dependencies.session.profiles() {
                me = profile
            }
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        // Stop this phone's pushes first, while the session can still reach the API (B5).
        await dependencies.push.unregister()
        await dependencies.session.signOut()
    }
}

/// Name and the viewer code, the code printed in the watermark of every image you're served.
struct SettingsProfileSummary: View {
    let me: Me?

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
            Text(me?.profile.firstName ?? " ")
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
            if let code = me?.profile.viewerCode {
                Text("Your viewer code: \(code)")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .accessibilityLabel(Text("Your viewer code: \(code.map(String.init).joined(separator: " "))"))
            }
        }
        .padding(.vertical, GlowSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isDanger = false
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, isDanger: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDanger = isDanger
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).glowFont(.body)
            } icon: {
                Image(systemName: systemImage)
            }
            .foregroundStyle(isDanger ? Color.glowDanger : Color.glowTextPrimary)
            .frame(maxWidth: .infinity, minHeight: GlowSize.minimumTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(Color.glowSurface)
    }
}

struct SettingsHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .glowFont(.footnote)
            .foregroundStyle(.glowTextSecondary)
    }
}

struct SettingsFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .glowFont(.footnote)
            .foregroundStyle(.glowTextSecondary)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .preferredColorScheme(.dark)
}
