import AppCore
import DesignSystem
import Session
import SwiftUI

/// Welcome, sign in, profile, photos and notifications, starting at `step`.
///
/// The app shows this while the session is signed out (`.welcome`) or onboarding (the server's
/// step), so a relaunch always resumes in the right place. Each step's screen moves the session
/// on by itself (the server's answer carries the next step), and the root follows.
public struct OnboardingFlowView: View {
    public let step: OnboardingStep

    public init(step: OnboardingStep) {
        self.step = step
    }

    public var body: some View {
        Group {
            switch step {
            case .welcome, .signIn:
                SignedOutFlow(startAtSignIn: step == .signIn)
            case .profile:
                NavigationStack { ProfileStepView() }
            case .photos:
                NavigationStack { PhotosStepView() }
            case .notifications:
                NavigationStack { NotificationsStepView() }
            }
        }
        .background(.glowBackground)
        .accessibilityIdentifier("screen.FeatureOnboarding")
    }
}

/// Welcome, then sign in, then the email code, as one navigation stack.
struct SignedOutFlow: View {
    enum Screen: Hashable {
        case signIn
        case email
        case code(email: String)
    }

    @State private var path: [Screen]

    init(startAtSignIn: Bool) {
        _path = State(initialValue: startAtSignIn ? [.signIn] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.signIn) }
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .signIn:
                        SignInView { path.append(.email) }
                    case .email:
                        EmailEntryView { email in path.append(.code(email: email)) }
                    case let .code(email):
                        CodeEntryView(email: email) { path.removeLast() }
                    }
                }
        }
        .tint(.glowAccent)
    }
}

/// The onboarding screen layout: a scrolling column of content, with the screen's actions
/// pinned at the bottom, above the keyboard.
struct OnboardingScreen<Content: View, Actions: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.top, GlowSpacing.lg)
                .padding(.bottom, GlowSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GlowSpacing.xs) {
                actions
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.sm)
            .padding(.bottom, GlowSpacing.sm)
            .background(.glowBackground)
        }
        .background(.glowBackground)
        .toolbarBackground(.glowBackground, for: .navigationBar)
    }
}

/// A short message under a form or a button: why something didn't work, in calm words.
struct InlineMessage: View {
    let text: Text
    var isError = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.xs) {
            Image(systemName: isError ? "exclamationmark.circle" : "info.circle")
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

#Preview("Welcome") {
    OnboardingFlowView(step: .welcome)
        .preferredColorScheme(.dark)
}
