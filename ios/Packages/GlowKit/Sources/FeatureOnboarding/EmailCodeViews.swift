import AppCore
import DesignSystem
import Session
import SwiftUI

/// Type your email; Glow sends a 6-digit code.
struct EmailEntryView: View {
    let codeSent: (String) -> Void

    @Environment(\.dependencies) private var dependencies
    @State private var email = ""
    @State private var isSending = false
    @State private var error: SessionError?
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScreen {
            EmailEntryContent(email: $email, error: error, focused: $focused, submit: send)
        } actions: {
            Button("Send code", action: send)
                .buttonStyle(.glowPrimary)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("email.send")
        }
        .glowLoading(isSending)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .accessibilityIdentifier("onboarding.email")
    }

    private func send() {
        Task { await sendCode() }
    }

    private func sendCode() async {
        error = nil
        isSending = true
        defer { isSending = false }
        do {
            try await dependencies.session.sendEmailCode(to: email)
            codeSent(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        } catch {
            self.error = error
        }
    }
}

struct EmailEntryContent: View {
    @Binding var email: String
    var error: SessionError?
    var focused: FocusState<Bool>.Binding
    var submit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text("What's your email?")
                    .glowFont(.title)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("We'll send you a 6-digit code. No password needed.")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
            }
            OnboardingTextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(submit)
                .focused(focused)
                .accessibilityLabel(Text("Email"))
                .accessibilityIdentifier("email.field")
            if let error {
                InlineMessage(text: Text(error.message))
            }
        }
    }
}

/// Type the 6-digit code from the email.
struct CodeEntryView: View {
    let email: String
    let changeEmail: () -> Void

    @Environment(\.dependencies) private var dependencies
    @State private var code = ""
    @State private var isWorking = false
    @State private var error: SessionError?
    @State private var resent = false
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScreen {
            CodeEntryContent(email: email, code: $code, error: error, resent: resent, focused: $focused)
        } actions: {
            Button("Sign in", action: verify)
                .buttonStyle(.glowPrimary)
                .disabled(code.filter(\.isNumber).count != 6)
                .accessibilityIdentifier("code.verify")
            HStack {
                Button("Send a new code", action: resend)
                    .buttonStyle(.glow(.quiet, size: .compact))
                    .accessibilityIdentifier("code.resend")
                Spacer()
                Button("Use another email", action: changeEmail)
                    .buttonStyle(.glow(.quiet, size: .compact))
            }
        }
        .glowLoading(isWorking)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onChange(of: code) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(6))
            if digits != new {
                code = digits
            }
            // A code from the keyboard's suggestion or a paste signs in at once.
            if digits.count == 6, !isWorking {
                verify()
            }
        }
        .accessibilityIdentifier("onboarding.code")
    }

    private func verify() {
        guard !isWorking else { return }
        Task { await verifyCode() }
    }

    private func verifyCode() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await dependencies.session.verifyEmailCode(code, email: email)
        } catch {
            self.error = error
            code = ""
        }
    }

    private func resend() {
        Task { await resendCode() }
    }

    private func resendCode() async {
        error = nil
        resent = false
        isWorking = true
        defer { isWorking = false }
        do {
            try await dependencies.session.sendEmailCode(to: email)
            resent = true
        } catch {
            self.error = error
        }
    }
}

struct CodeEntryContent: View {
    let email: String
    @Binding var code: String
    var error: SessionError?
    var resent = false
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text("Enter your code")
                    .glowFont(.title)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("We sent a 6-digit code to \(email). It works for an hour.")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("000000", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .glowFont(.code)
                .kerning(8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.glowTextPrimary)
                .padding(.vertical, GlowSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: GlowSize.buttonHeight)
                .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
                .overlay(RoundedRectangle(cornerRadius: GlowRadius.control).strokeBorder(.glowLine))
                .focused(focused)
                .accessibilityLabel(Text("6-digit code"))
                .accessibilityIdentifier("code.field")
            if let error {
                InlineMessage(text: Text(error.message))
            } else if resent {
                InlineMessage(text: Text("A new code is on its way."), isError: false)
            }
        }
    }
}

/// A single-line text field in the onboarding style.
struct OnboardingTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    init(_ placeholder: LocalizedStringKey, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .glowFont(.body)
            .foregroundStyle(.glowTextPrimary)
            .padding(.horizontal, GlowSpacing.md)
            .frame(minHeight: GlowSize.buttonHeight)
            .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.control))
            .overlay(RoundedRectangle(cornerRadius: GlowRadius.control).strokeBorder(.glowLine))
    }
}
