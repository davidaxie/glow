import APIClient
import AppCore
import DesignSystem
import Session
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureOnboarding

/// Every onboarding screen at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/OnboardingSnapshotTests`
/// and run `scripts/sim.sh test FeatureOnboarding` twice (the first run records and fails).
@MainActor
struct OnboardingSnapshotTests {
    enum Screen: String, CaseIterable {
        case welcome
        case signIn
        case signInError
        case email
        case code
        case profileEmpty
        case profileFilled
        case underAge
        case photosEmpty
        case photosHeld
        case notifications
    }

    @Test(arguments: Screen.allCases, [DynamicTypeSize.large, .accessibility5])
    func screen(_ screen: Screen, size: DynamicTypeSize) {
        let view = content(for: screen)
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
            named: "\(screen.rawValue)-\(size == .large ? "default" : "ax5")",
        )
    }

    @ViewBuilder
    private func content(for screen: Screen) -> some View { // swiftlint:disable:this cyclomatic_complexity
        switch screen {
        case .welcome: WelcomeContent()
        case .signIn: SignInContent()
        case .signInError: SignInContent(error: .invalidCode)
        case .email: FocusHost { EmailEntryContent(email: .constant("robin@example.com"), focused: $0) }
        case .code: CodeEntryContent(email: "robin@example.com", code: .constant("12"))
        case .profileEmpty: ProfileStepContentPreview(form: ProfileForm(now: { Self.fixedNow }))
        case .profileFilled: ProfileStepContentPreview(form: Self.filledForm())
        case .underAge: UnderAgeContent()
        case .photosEmpty: PhotosStepContent(slots: PhotoSlots(), add: { _, _ in }, remove: { _ in })
        case .photosHeld: PhotosStepContent(slots: Self.heldSlots(), add: { _, _ in }, remove: { _ in })
        case .notifications: NotificationsStepContent()
        }
    }

    /// A fixed "today", so the date picker reads the same on every run.
    nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_793_037_600) // 2026-10-24T18:00:00Z

    static func filledForm() -> ProfileForm {
        let form = ProfileForm(existing: Me.preview(step: .photos).profile, now: { fixedNow })
        form.showMe = [.woman, .man]
        return form
    }

    static func heldSlots() -> PhotoSlots {
        PhotoSlots(photos: [
            .init(id: "0f0f0f0f-0000-4000-8000-0000000000b1", position: 0, moderationStatus: .held, url: "/api/me/photos/x"),
        ])
    }
}

/// The profile step's content without the scroll view, for snapshots.
private struct ProfileStepContentPreview: View {
    let form: ProfileForm

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            GlowStepHeader(step: 1, of: 3, title: "About you", subtitle: "Only people you match with ever see your first name.")
            ProfileFields(form: form)
        }
    }
}

/// Owns a FocusState for content views that take a binding to one.
private struct FocusHost<Content: View>: View {
    @FocusState private var focused: Bool
    let content: (FocusState<Bool>.Binding) -> Content

    init(@ViewBuilder content: @escaping (FocusState<Bool>.Binding) -> Content) {
        self.content = content
    }

    var body: some View {
        content($focused)
    }
}

@MainActor
struct OnboardingFlowTests {
    @Test func entryViewStartsAtTheGivenStep() {
        #expect(OnboardingFlowView(step: .photos).step == .photos)
    }

    @Test func everyStepBuilds() {
        for step in OnboardingStep.allCases {
            _ = OnboardingFlowView(step: step).body
        }
    }

    @Test func signInErrorsSayWhatToDoNext() {
        for error in [SessionError.invalidEmail, .invalidCode, .rateLimited, .offline, .appleSignInFailed, .notConfigured, .unexpected] {
            _ = error.message
        }
    }

    @Test func noPhotoErrorBlamesThePerson() {
        // Every rejection reason has calm copy, including ones the server adds later (.other).
        for reason in [PhotoRejection.nudity, .noPerson, .unreadable, .other, .faceVisible, .noOutfit, .possiblyMinor] {
            _ = ProfileError.photoRejected(reason).message
        }
    }
}
