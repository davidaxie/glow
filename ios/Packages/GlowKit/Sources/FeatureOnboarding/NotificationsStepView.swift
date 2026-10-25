import APIClient
import AppCore
import DesignSystem
import Session
import SwiftUI

/// Step 3 of 3: ask for notification permission (B5's Push registers the token), then finish.
/// "Not now" finishes too: declining notifications never blocks anyone.
struct NotificationsStepView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var isFinishing = false
    @State private var error: ProfileError?

    var body: some View {
        OnboardingScreen(identifier: "onboarding.notifications") {
            NotificationsStepContent(error: error)
        } actions: {
            Button("Turn on notifications") {
                Task { await finish(askForPermission: true) }
            }
            .buttonStyle(.glowPrimary)
            .accessibilityIdentifier("notifications.allow")
            Button("Not now") {
                Task { await finish(askForPermission: false) }
            }
            .buttonStyle(.glowQuiet)
            .accessibilityIdentifier("notifications.skip")
        }
        .glowLoading(isFinishing)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func finish(askForPermission: Bool) async {
        error = nil
        isFinishing = true
        defer { isFinishing = false }
        var allowed = false
        if askForPermission {
            // Whatever the answer (or an error), onboarding goes on.
            let answer = try? await dependencies.push.requestAuthorization()
            allowed = answer == .authorized || answer == .provisional
        }
        do {
            // The server's answer is `complete`, which moves the app to the tabs.
            try await ProfileClient(api: dependencies.api, session: dependencies.session).finishOnboarding()
            dependencies.analytics.track(AnalyticsEvent("onboarding_finished", ["notifications": .bool(allowed)]))
        } catch .onboardingIncomplete {
            // Something earlier isn't done after all (a photo is still being checked, say):
            // refetch, and the app goes back to that step.
            _ = try? await dependencies.session.refreshProfile()
            error = .onboardingIncomplete
        } catch {
            self.error = error
        }
    }
}

struct NotificationsStepContent: View {
    var error: ProfileError?
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            GlowStepHeader(
                step: 3,
                of: OnboardingProgress.steps,
                title: "Know when it's mutual",
                subtitle: "We'll tell you the moment someone you noticed notices you back.",
            )
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                NotificationPoint(systemImage: "bell.badge", text: "A buzz when it's mutual, and when it's time to find each other.")
                NotificationPoint(systemImage: "eye.slash", text: "Lock screen messages never include a name or a photo.")
                NotificationPoint(systemImage: "gearshape", text: "You can change this any time in the Settings app.")
            }
            if let error {
                InlineMessage(text: Text(error.message))
            }
        }
    }
}

private struct NotificationPoint: View {
    let systemImage: String
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(.glowAccent)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .glowFont(.body)
                .foregroundStyle(.glowTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
