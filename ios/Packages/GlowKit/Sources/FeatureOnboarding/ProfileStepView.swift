import APIClient
import AppCore
import DesignSystem
import Session
import SwiftUI

/// Step 1 of 3: first name, birthday, gender and who you want to see.
///
/// Under 18 never reaches the server: the phone checks first and shows a kind message instead,
/// and the profile step then stays closed on this phone (P10, B1-D2). The server and the
/// database refuse it too.
struct ProfileStepView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var form = ProfileForm()
    @State private var gateClosed = AgeGateLock().isClosed

    var body: some View {
        Group {
            if gateClosed || form.phase == .underAge {
                UnderAgeView()
            } else {
                OnboardingScreen {
                    VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                        GlowStepHeader(
                            step: 1,
                            of: OnboardingProgress.steps,
                            title: "About you",
                            subtitle: "Only people you match with ever see your first name.",
                        )
                        ProfileFields(form: form)
                        if let error = form.error {
                            InlineMessage(text: Text(error.message))
                        }
                    }
                } actions: {
                    Button("Continue") {
                        Task { await save() }
                    }
                    .buttonStyle(.glowPrimary)
                    .disabled(!form.isComplete)
                    .accessibilityIdentifier("profile.continue")
                }
                .glowLoading(form.phase == .saving)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("onboarding.profile")
        .task {
            // Coming back to a half-filled profile: start from what was saved.
            if form.trimmedName.isEmpty, let saved = await dependencies.session.currentProfile()?.profile {
                form = ProfileForm(existing: saved)
            }
            #if DEBUG
                // UI tests: `-GlowTestBirthday YYYY-MM-DD` picks the date without the wheel.
                if let raw = UserDefaults.standard.string(forKey: "GlowTestBirthday"),
                   let date = ProfileForm.date(fromISO: raw)
                {
                    form.pickBirthday(date)
                }
            #endif
        }
    }

    private func save() async {
        let client = ProfileClient(api: dependencies.api, session: dependencies.session)
        // On success the server's answer moves the session to the photos step.
        await form.save(using: client, closeGate: AgeGateLock())
        if form.phase == .underAge {
            dependencies.analytics.track(AnalyticsEvent("onboarding_under_18"))
            gateClosed = true
        } else if form.error == nil {
            dependencies.analytics.track(AnalyticsEvent("onboarding_step_done", ["step": "profile"]))
        }
    }
}

/// The profile fields, also used for snapshots.
struct ProfileFields: View {
    @Bindable var form: ProfileForm

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            FieldGroup(title: "First name") {
                OnboardingTextField("Your first name", text: $form.firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel(Text("First name"))
                    .accessibilityIdentifier("profile.firstName")
            }

            FieldGroup(
                title: "Birthday",
                note: "Only used to check you're 18 or older. Nobody else sees it.",
            ) {
                BirthdayRow(form: form)
                    .accessibilityIdentifier("profile.birthday")
            }

            FieldGroup(title: "I am") {
                ChoiceChips(
                    options: GenderCopy.selfOptions,
                    isSelected: { form.gender == $0 },
                    toggle: { form.gender = $0 },
                    identifier: "profile.gender",
                )
            }

            FieldGroup(title: "Show me", note: "Pick everyone you'd like to see. You can change it later.") {
                ChoiceChips(
                    options: GenderCopy.showMeOptions,
                    isSelected: { form.showMe.contains($0) },
                    toggle: { form.toggleShowMe($0) },
                    identifier: "profile.showMe",
                )
            }
        }
    }
}

/// The birthday: a row that shows the picked date (or "Choose"), and opens a wheel picker under
/// it. The row is plain text, so it grows with Dynamic Type at every size.
struct BirthdayRow: View {
    @Bindable var form: ProfileForm
    @State private var isPicking = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                        label
                        value
                    }
                } else {
                    HStack(spacing: GlowSpacing.sm) {
                        label
                        Spacer(minLength: 0)
                        value
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GlowSpacing.md)
            .padding(.vertical, GlowSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: GlowSize.buttonHeight, alignment: .leading)
            .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
            .contentShape(RoundedRectangle(cornerRadius: GlowRadius.control))
            // A tap target rather than a Button, so the row sizes with its text at every size.
            .onTapGesture { isPicking.toggle() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isPicking.toggle() }
            .accessibilityLabel(Text("Birthday"))
            .accessibilityValue(
                form.birthdayChosen ? Text(form.birthday, format: .dateTime.day().month(.wide).year()) : Text("Not chosen"),
            )
            .accessibilityHint(Text("Shows a date picker"))

            if isPicking {
                DatePicker(
                    selection: Binding(get: { form.birthday }, set: { form.pickBirthday($0) }),
                    in: ...form.latestBirthday,
                    displayedComponents: .date,
                ) {
                    Text("Birthday")
                }
                .labelsHidden()
                .datePickerStyle(.wheel)
                .tint(.glowAccent)
                .frame(maxWidth: .infinity)
                .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
            }
        }
    }

    private var label: some View {
        Text("Birthday")
            .glowFont(.body)
            .foregroundStyle(.glowTextPrimary)
    }

    @ViewBuilder private var value: some View {
        if form.birthdayChosen {
            Text(form.birthday, format: .dateTime.day().month(.abbreviated).year())
                .glowFont(.body)
                .foregroundStyle(.glowAccent)
        } else {
            Text("Choose")
                .glowFont(.body)
                .foregroundStyle(.glowTextSecondary)
        }
    }
}

/// A labeled group of controls.
struct FieldGroup<Content: View>: View {
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

/// A wrapping row of chips for picking genders.
struct ChoiceChips: View {
    let options: [GenderOption]
    let isSelected: (Components.Schemas.Gender) -> Bool
    let toggle: (Components.Schemas.Gender) -> Void
    let identifier: String

    var body: some View {
        GlowFlowLayout {
            ForEach(options) { option in
                GlowChip(option.title, isSelected: isSelected(option.value)) { toggle(option.value) }
                    .accessibilityIdentifier("\(identifier).\(option.value.rawValue)")
            }
        }
    }
}

struct GenderOption: Identifiable {
    let value: Components.Schemas.Gender
    let title: LocalizedStringKey

    var id: String {
        value.rawValue
    }
}

enum GenderCopy {
    static var selfOptions: [GenderOption] {
        [
            GenderOption(value: .woman, title: "Woman"),
            GenderOption(value: .man, title: "Man"),
            GenderOption(value: .nonbinary, title: "Nonbinary"),
        ]
    }

    static var showMeOptions: [GenderOption] {
        [
            GenderOption(value: .woman, title: "Women"),
            GenderOption(value: .man, title: "Men"),
            GenderOption(value: .nonbinary, title: "Nonbinary people"),
        ]
    }
}

enum OnboardingProgress {
    /// Profile, photos, notifications.
    static let steps = 3
}

/// Under 18: a kind message, and no way forward. Nothing about the answer was stored.
struct UnderAgeView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var isSigningOut = false

    var body: some View {
        OnboardingScreen {
            UnderAgeContent()
        } actions: {
            Button("Sign out") {
                Task {
                    isSigningOut = true
                    await dependencies.push.unregister()
                    await dependencies.session.signOut()
                }
            }
            .buttonStyle(.glowSecondary)
            .glowLoading(isSigningOut)
            .accessibilityIdentifier("underAge.signOut")
        }
        .navigationBarBackButtonHidden()
        .accessibilityIdentifier("onboarding.underAge")
    }
}

struct UnderAgeContent: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            Image(systemName: "heart")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.glowAccent)
                .accessibilityHidden(true)
                .padding(.top, GlowSpacing.xl)
            Text("Glow is for adults")
                .glowFont(.title)
                .foregroundStyle(.glowTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Thanks for being honest. Glow is only for people 18 and older, so we can't set up a profile for you.")
                .glowFont(.body)
                .foregroundStyle(.glowTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your birthday wasn't saved or sent anywhere.")
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension ProfileError {
    /// What the profile and photo screens say.
    var message: LocalizedStringKey {
        switch self {
        case .under18: "Glow is only for people 18 and older."
        case .invalid: "Something in there didn't look right. Check it and try again."
        case let .photoRejected(reason): reason.message
        case .photoTooLarge: "That photo is too large. Try another one."
        case .moderationUnavailable: "We couldn't check that photo just now. Try again in a moment."
        case .lastPhoto: "Add another photo before removing this one."
        case .onboardingIncomplete: "Add a photo that's been approved first."
        case .conflict: "Something changed at the same moment. Try again."
        case .notFound: "That photo isn't there anymore."
        case .offline: "You're offline. Try again when you're connected."
        case .rateLimited: "That's a lot of changes. Wait a minute, then try again."
        case .signedOut: "You've been signed out. Sign in again to keep going."
        case .unexpected: "Something went wrong on our side. Try again in a moment."
        }
    }
}

extension PhotoRejection {
    var message: LocalizedStringKey {
        switch self {
        case .noPerson: "We couldn't see anyone in that photo. Try one of you."
        case .unreadable: "That photo couldn't be opened. Try another one."
        case .nudity, .faceVisible, .noOutfit, .possiblyMinor, .other: "That photo can't be used. Try another one."
        }
    }
}
