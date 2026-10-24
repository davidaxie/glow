import APIClient
import AppCore
import DesignSystem
import Session
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureSettings

@MainActor
struct FeatureSettingsTests {
    @Test func entryViewsBuild() {
        _ = SettingsView().body
        _ = EditProfileView().body
        _ = EditPhotosView().body
    }

    @Test(arguments: ["edit-profile", "edit-photos", "summary"], [DynamicTypeSize.large, .accessibility5])
    func snapshot(_ name: String, size: DynamicTypeSize) {
        let view = content(name)
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.lg)
            .frame(width: 393)
            .background(.glowBackground)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = .dark
                    traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
                },
            ),
            named: "\(name)-\(size == .large ? "default" : "ax5")",
        )
    }

    @ViewBuilder
    private func content(_ name: String) -> some View {
        switch name {
        case "edit-profile":
            SettingsProfileFields(form: ProfileForm(
                existing: Me.preview(step: .complete).profile,
                now: { ISO8601DateFormatter().date(from: "2026-10-24T18:00:00Z")! },
            ))
        case "edit-photos":
            EditPhotosContent(
                slots: PhotoSlots(photos: [
                    .init(id: "0f0f0f0f-0000-4000-8000-0000000000b2", position: 1, moderationStatus: .held, url: "/api/me/photos/x"),
                ]),
                add: { _, _ in },
                remove: { _ in },
            )
        default:
            SettingsProfileSummary(me: Me.preview(step: .complete))
        }
    }

    @Test func everyProfileErrorHasSettingsCopy() {
        let errors: [ProfileError] = [
            .under18, .invalid, .photoRejected(.nudity), .photoRejected(.noPerson), .photoRejected(.unreadable),
            .photoTooLarge, .moderationUnavailable, .lastPhoto, .onboardingIncomplete, .conflict, .notFound,
            .offline, .rateLimited, .signedOut, .unexpected,
        ]
        for error in errors {
            _ = error.settingsMessage
        }
    }
}
