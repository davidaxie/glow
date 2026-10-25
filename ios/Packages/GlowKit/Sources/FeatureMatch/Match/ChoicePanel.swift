import AppCore
import DesignSystem
import SwiftUI
import UIKit

/// The two choices, each with one line explaining it, or the waiting state once I chose Find.
struct ChoicePanel: View {
    @Bindable var model: MatchModel
    let snapshot: MatchSnapshot

    var body: some View {
        VStack(spacing: GlowSpacing.md) {
            switch model.phase {
            case .waiting:
                WaitingPanel(model: model, snapshot: snapshot)
            case let .moved(route):
                MovedPanel(route: route)
            default:
                choices
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sending: MatchSnapshot.Choice? {
        if case let .sending(choice) = model.phase {
            return choice
        }
        return nil
    }

    @ViewBuilder private var choices: some View {
        VStack(spacing: GlowSpacing.xs) {
            Button("Find each other") { Task { await model.chooseFind() } }
                .buttonStyle(.glowPrimary)
                .glowLoading(sending == .find)
                .disabled(sending == .chat)
                .accessibilityHint(Text("Your screens glow the same color so you can spot each other, if they pick it too."))
            Text("Your screens glow the same color so you can spot each other. Only if you both pick it.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }

        VStack(spacing: GlowSpacing.xs) {
            Button("Just chat") { Task { await model.chooseChat() } }
                .buttonStyle(.glowSecondary)
                .glowLoading(sending == .chat)
                .disabled(sending == .find)
                .accessibilityHint(Text("Opens a chat with them. You can still meet whenever you like."))
            Text("Say hi here first. You can still meet whenever you like.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }

        if let notice = model.notice {
            NoticeView(notice: notice)
        }

        ChoiceCountdown(deadline: snapshot.choiceDeadline, style: .quiet)
    }
}

/// I chose Find; waiting for them, with the 10-minute countdown.
struct WaitingPanel: View {
    @Bindable var model: MatchModel
    let snapshot: MatchSnapshot

    var body: some View {
        VStack(spacing: GlowSpacing.md) {
            VStack(spacing: GlowSpacing.xs) {
                Text("You chose Find each other.")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Text("Waiting for \(Text(verbatim: snapshot.firstName)) to choose.")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            // A breathing light behind the clock: waiting, not loading.
            ChoiceCountdown(deadline: snapshot.choiceDeadline, style: .prominent)
                .padding(.vertical, GlowSpacing.sm)
                .background {
                    MomentLight(core: 0.5)
                        .frame(width: 220, height: 220)
                        .opacity(0.55)
                        .momentBreathing()
                }

            Text("If time runs out, the chat opens.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .multilineTextAlignment(.center)

            if let notice = model.notice {
                NoticeView(notice: notice)
            }

            Button("Just chat instead") { Task { await model.chooseChat() } }
                .buttonStyle(.glowQuiet)
        }
        .padding(GlowSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(.glowSurface, in: .rect(cornerRadius: MomentSurface.radius, style: .continuous))
        .clipShape(.rect(cornerRadius: MomentSurface.radius, style: .continuous))
        .overlay { MomentSurface.highlight }
    }
}

/// A lifted glass surface: large continuous corners and a 1 pt highlight along the top edge.
enum MomentSurface {
    static let radius: CGFloat = 28

    static var highlight: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [GlowPalette.textPrimary.color.opacity(0.16), GlowPalette.textPrimary.color.opacity(0)],
                    startPoint: .top,
                    endPoint: .center,
                ),
                lineWidth: 1,
            )
            .accessibilityHidden(true)
    }
}

/// Choosing is over. The screen is about to move on; this covers the moment, and the way back.
struct MovedPanel: View {
    let route: Route
    @Environment(\.navigate) private var navigate

    var body: some View {
        VStack(spacing: GlowSpacing.sm) {
            switch route {
            case .glow:
                Text("You both chose Find each other.")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Button("Open the glow") { navigate(route) }
                    .buttonStyle(.glowPrimary)
            default:
                Text("Your chat is open.")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Button("Open the chat") { navigate(route) }
                    .buttonStyle(.glowPrimary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

extension EnvironmentValues {
    /// A fixed "now" for the countdowns, so snapshot tests don't depend on the clock. Nil means
    /// the real time, ticking.
    @Entry var matchClockOverride: Date?
}

/// The time left to choose, ticking once a second.
struct ChoiceCountdown: View {
    enum Style {
        /// A small line under the choices.
        case quiet
        /// Big digits while waiting.
        case prominent
    }

    let deadline: Date
    let style: Style
    @Environment(\.matchClockOverride) private var fixedNow

    var body: some View {
        if let fixedNow {
            label(at: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(at: context.date)
            }
        }
    }

    private func label(at now: Date) -> some View {
        let left = max(0, deadline.timeIntervalSince(now))
        let clock = Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond))
        return Group {
            switch style {
            case .quiet:
                Text("\(clock) left to choose")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .monospacedDigit()
            case .prominent:
                Text(verbatim: clock)
                    .glowFont(.display)
                    .foregroundStyle(.glowTextPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Moment.snappy, value: clock)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time left to choose"))
        .accessibilityValue(Text(Self.spoken(left)))
    }

    /// "8 minutes, 12 seconds", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// A calm note after something didn't work, with what to do next.
struct NoticeView: View {
    let notice: MatchModel.Notice
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: GlowSpacing.xs) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: icon)
            }
            .glowFont(.callout)
            .foregroundStyle(.glowTextPrimary)
            .multilineTextAlignment(.leading)

            if notice == .locationDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(settings) }
                    .buttonStyle(.glow(.quiet, size: .compact))
            }
        }
        .padding(GlowSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.glowSurfaceRaised, in: .rect(cornerRadius: GlowRadius.control, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var message: LocalizedStringKey {
        switch notice {
        case .notInRoom: "Looks like you're not in this room yet. Try again inside."
        case .locationDenied: "Find each other checks once that you're both in the room. Allow location in Settings, or just chat."
        case .locationUnavailable: "Couldn't get a good location fix. Try again in a moment."
        case .offline: "You're offline. Try again in a moment."
        case .slowDown: "One moment. Try again shortly."
        case .failed: "Something went wrong. Try again."
        }
    }

    private var icon: String {
        switch notice {
        case .notInRoom, .locationDenied, .locationUnavailable: "location.slash"
        case .offline: "wifi.slash"
        case .slowDown: "hourglass"
        case .failed: "exclamationmark.circle"
        }
    }
}
