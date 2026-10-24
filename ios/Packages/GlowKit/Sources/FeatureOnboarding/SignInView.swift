import AppCore
import AuthenticationServices
import DesignSystem
import Session
import SwiftUI

/// Sign in with Apple, or with a 6-digit email code. New and returning people take the same path.
struct SignInView: View {
    let useEmail: () -> Void

    @Environment(\.dependencies) private var dependencies
    @State private var nonce = AppleSignInNonce.make()
    @State private var isSigningIn = false
    @State private var error: SessionError?

    var body: some View {
        OnboardingScreen {
            SignInContent(error: error)
        } actions: {
            SignInWithAppleButton(.continue) { request in
                nonce = AppleSignInNonce.make()
                // No name and no email: Glow asks for a first name itself, and needs nothing else
                // from your Apple ID (B1-D3).
                request.requestedScopes = []
                request.nonce = nonce.hashed
            } onCompletion: { result in
                Task { await finishApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: GlowSize.buttonHeight)
            .clipShape(RoundedRectangle(cornerRadius: GlowRadius.control))
            .disabled(isSigningIn)
            .accessibilityIdentifier("signIn.apple")

            Button("Continue with email", action: useEmail)
                .buttonStyle(.glowSecondary)
                .accessibilityIdentifier("signIn.email")

            #if DEBUG
                TestSignInPanel()
            #endif
        }
        .glowLoading(isSigningIn)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("onboarding.signIn")
    }

    private func finishApple(_ result: Result<ASAuthorization, any Error>) async {
        error = nil
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                error = .appleSignInFailed
                return
            }
            isSigningIn = true
            defer { isSigningIn = false }
            do {
                try await dependencies.session.signInWithApple(idToken: idToken, nonce: nonce.raw)
            } catch {
                self.error = error
            }
        case let .failure(failure):
            // Cancelling isn't an error worth a message.
            if (failure as? ASAuthorizationError)?.code != .canceled {
                error = .appleSignInFailed
            }
        }
    }
}

/// The sign-in screen's words.
struct SignInContent: View {
    var error: SessionError?

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text("Sign in")
                    .glowFont(.title)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("New here or coming back, it's the same few taps.")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
            }
            Text("Glow never shows your Apple ID or email to anyone. An email is only used to send you sign-in codes.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                InlineMessage(text: Text(error.message))
            }
        }
    }
}

extension SessionError {
    /// What the sign-in screens say. Calm, and never blames the person.
    var message: LocalizedStringKey {
        switch self {
        case .invalidEmail: "That doesn't look like an email address. Check it and try again."
        case .invalidCode: "That code didn't work. Check the latest email, or send a new code."
        case .rateLimited: "That's a lot of tries. Wait a minute, then try again."
        case .offline: "You're offline. Try again when you're connected."
        case .appleSignInFailed: "Sign in with Apple didn't finish. Try again, or continue with email."
        case .notConfigured: "Sign-in isn't set up in this build."
        case .unexpected: "Something went wrong on our side. Try again in a moment."
        }
    }
}

#if DEBUG
    /// Debug builds only: sign in a `@glow.test` person through `POST /api/dev/test-login`
    /// (the server needs `ALLOW_TEST_LOGIN`). Compiled out of Release.
    private struct TestSignInPanel: View {
        @Environment(\.dependencies) private var dependencies
        @State private var email = "new@glow.test"
        @State private var isSigningIn = false
        @State private var error: SessionError?

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text("Debug: test sign-in")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                HStack(spacing: GlowSpacing.xs) {
                    TextField("test@glow.test", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .glowFont(.callout)
                        .foregroundStyle(.glowTextPrimary)
                        .padding(.horizontal, GlowSpacing.sm)
                        .frame(minHeight: GlowSize.compactButtonHeight)
                        .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
                        .accessibilityIdentifier("signIn.test.email")
                    Button("Sign in") {
                        Task {
                            isSigningIn = true
                            defer { isSigningIn = false }
                            do {
                                try await dependencies.session.signInForTesting(email: email)
                            } catch {
                                self.error = error
                            }
                        }
                    }
                    .buttonStyle(.glow(.secondary, size: .compact))
                    .glowLoading(isSigningIn)
                    .accessibilityIdentifier("signIn.test.button")
                }
                if let error {
                    InlineMessage(text: Text(error.message))
                }
            }
            .padding(.top, GlowSpacing.sm)
        }
    }
#endif

#Preview {
    NavigationStack { SignInView {} }
        .preferredColorScheme(.dark)
}
