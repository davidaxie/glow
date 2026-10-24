import APIClient
import AppCore
import DesignSystem
import Session
import SwiftUI

/// Settings → Edit profile: the same fields as onboarding, saved with `PUT /api/me/profile`.
/// The 18+ rule applies here too: an under-18 birthday is refused and nothing is saved.
public struct EditProfileView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var form: ProfileForm?
    @State private var saved = false

    public init() {}

    public var body: some View {
        Group {
            if let form {
                EditProfileForm(form: form, saved: saved) {
                    Task { await save(form) }
                }
            } else {
                ProgressView()
                    .tint(.glowAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.glowBackground)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.editProfileScreen")
        .task {
            if form == nil {
                let profile = await dependencies.session.currentProfile()?.profile
                form = ProfileForm(existing: profile)
            }
        }
    }

    private func save(_ form: ProfileForm) async {
        saved = false
        let client = ProfileClient(api: dependencies.api, session: dependencies.session)
        if await form.save(using: client) {
            saved = true
            dependencies.analytics.track(AnalyticsEvent("profile_edited"))
        }
    }
}

struct EditProfileForm: View {
    @Bindable var form: ProfileForm
    var saved = false
    var save: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                SettingsProfileFields(form: form)
                if form.phase == .underAge {
                    SettingsMessage(text: Text("Glow is only for people 18 and older, so that birthday can't be saved. Nothing was changed."))
                } else if let error = form.error {
                    SettingsMessage(text: Text(error.settingsMessage))
                } else if saved {
                    SettingsMessage(text: Text("Saved."), isError: false)
                }
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Save") {
                if form.phase == .underAge {
                    form.dismissUnderAge()
                }
                save()
            }
            .buttonStyle(.glowPrimary)
            .disabled(!form.isComplete || form.phase == .saving)
            .glowLoading(form.phase == .saving)
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.sm)
            .background(.glowBackground)
            .accessibilityIdentifier("editProfile.save")
        }
        .onChange(of: form.birthday) {
            if form.phase == .underAge {
                form.dismissUnderAge()
            }
        }
    }
}

/// The profile fields, in Settings' style.
struct SettingsProfileFields: View {
    @Bindable var form: ProfileForm

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            SettingsField(title: "First name", note: "Only people you match with see it.") {
                TextField("Your first name", text: $form.firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .glowFont(.body)
                    .foregroundStyle(.glowTextPrimary)
                    .padding(.horizontal, GlowSpacing.md)
                    .frame(minHeight: GlowSize.buttonHeight)
                    .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
                    .accessibilityLabel(Text("First name"))
                    .accessibilityIdentifier("editProfile.firstName")
            }
            SettingsField(title: "Birthday", note: "Only used to check you're 18 or older. Nobody else sees it.") {
                DatePicker(
                    selection: Binding(get: { form.birthday }, set: { form.pickBirthday($0) }),
                    in: ...form.latestBirthday,
                    displayedComponents: .date,
                ) {
                    Text("Birthday")
                        .glowFont(.body)
                        .foregroundStyle(.glowTextPrimary)
                }
                .datePickerStyle(.compact)
                .tint(.glowAccent)
                .padding(.horizontal, GlowSpacing.md)
                .frame(minHeight: GlowSize.buttonHeight)
                .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
                .accessibilityIdentifier("editProfile.birthday")
            }
            SettingsField(title: "I am") {
                SettingsGenderChips(options: SettingsGenderCopy.selfOptions, isSelected: { form.gender == $0 }) {
                    form.gender = $0
                }
            }
            SettingsField(title: "Show me") {
                SettingsGenderChips(options: SettingsGenderCopy.showMeOptions, isSelected: { form.showMe.contains($0) }) {
                    form.toggleShowMe($0)
                }
            }
        }
    }
}

struct SettingsField<Content: View>: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            Text(title)
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
                .accessibilityAddTraits(.isHeader)
            content
            if let note {
                Text(note)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsGenderOption: Identifiable {
    let value: Components.Schemas.Gender
    let title: LocalizedStringKey

    var id: String {
        value.rawValue
    }
}

enum SettingsGenderCopy {
    static var selfOptions: [SettingsGenderOption] {
        [
            SettingsGenderOption(value: .woman, title: "Woman"),
            SettingsGenderOption(value: .man, title: "Man"),
            SettingsGenderOption(value: .nonbinary, title: "Nonbinary"),
        ]
    }

    static var showMeOptions: [SettingsGenderOption] {
        [
            SettingsGenderOption(value: .woman, title: "Women"),
            SettingsGenderOption(value: .man, title: "Men"),
            SettingsGenderOption(value: .nonbinary, title: "Nonbinary people"),
        ]
    }
}

struct SettingsGenderChips: View {
    let options: [SettingsGenderOption]
    let isSelected: (Components.Schemas.Gender) -> Bool
    let toggle: (Components.Schemas.Gender) -> Void

    var body: some View {
        GlowFlowLayout {
            ForEach(options) { option in
                GlowChip(option.title, isSelected: isSelected(option.value)) { toggle(option.value) }
            }
        }
    }
}

struct SettingsMessage: View {
    let text: Text
    var isError = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.xs) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                .accessibilityHidden(true)
            text
        }
        .glowFont(.callout)
        .foregroundStyle(isError ? Color.glowDanger : Color.glowTextSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension ProfileError {
    var settingsMessage: LocalizedStringKey {
        switch self {
        case .under18: "Glow is only for people 18 and older, so that can't be saved."
        case .invalid: "Something in there didn't look right. Check it and try again."
        case .photoRejected(.noPerson): "We couldn't see anyone in that photo. Try one of you."
        case .photoRejected(.unreadable): "That photo couldn't be opened. Try another one."
        case .photoRejected: "That photo can't be used. Try another one."
        case .photoTooLarge: "That photo is too large. Try another one."
        case .moderationUnavailable: "We couldn't check that photo just now. Try again in a moment."
        case .lastPhoto: "Add another photo before removing this one. Your profile always keeps at least one."
        case .onboardingIncomplete: "Finish your profile first."
        case .conflict: "Something changed at the same moment. Try again."
        case .notFound: "That photo isn't there anymore."
        case .offline: "You're offline. Try again when you're connected."
        case .rateLimited: "That's a lot of changes. Wait a minute, then try again."
        case .signedOut: "You've been signed out. Sign in again to keep going."
        case .unexpected: "Something went wrong on our side. Try again in a moment."
        }
    }
}
