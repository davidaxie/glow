import ActivityKit
import DesignSystem
import LiveActivityShared
import SwiftUI
import WidgetKit

// Owner: C3. The lock screen and Dynamic Island views for the glow countdown.
//
// Only what's already on the glow screen: the color, the code word, the meeting spot and the time.
// Never a name (P6). The words come from `GlowActivityDisplay` (LiveActivityShared), which is
// unit-tested; this file only draws them.

@main
struct GlowLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        GlowCountdownActivity()
    }
}

struct GlowCountdownActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlowActivityAttributes.self) { context in
            GlowLockScreenView(display: display(context), hue: hue(context))
                .activityBackgroundTint(hue(context).color)
                .activitySystemActionForegroundColor(hue(context).ink.color)
        } dynamicIsland: { context in
            let display = display(context)
            let hue = hue(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlowDot(hue: hue, size: 28)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if display.showsCountdown {
                        GlowTimer(display: display)
                            .font(.glow(.headline))
                            .frame(maxWidth: 72)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(verbatim: display.codeWord)
                        .font(.system(.title2, design: .rounded, weight: .heavy))
                        .foregroundStyle(hue.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text(display.headline)
                            .font(.glow(.headline))
                        if let detail = display.detail {
                            Text(detail)
                                .font(.glow(.callout))
                                .foregroundStyle(.glowTextSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            } compactLeading: {
                GlowDot(hue: hue, size: 18)
            } compactTrailing: {
                if display.showsCountdown {
                    GlowTimer(display: display)
                        .frame(maxWidth: 44)
                        .foregroundStyle(hue.color)
                } else {
                    Image(systemName: display.phase == .met ? "sparkles" : "checkmark")
                        .foregroundStyle(hue.color)
                }
            } minimal: {
                GlowDot(hue: hue, size: 18)
            }
            .keylineTint(hue.color)
        }
    }

    private func display(_ context: ActivityViewContext<GlowActivityAttributes>) -> GlowActivityDisplay {
        GlowActivityDisplay(attributes: context.attributes, state: context.state, now: .now, isStale: context.isStale)
    }

    private func hue(_ context: ActivityViewContext<GlowActivityAttributes>) -> GlowHue {
        GlowHue(rawValue: context.attributes.color) ?? .pearl
    }
}

/// The lock screen banner: on the glow color, in its ink, like the glow screen.
struct GlowLockScreenView: View {
    let display: GlowActivityDisplay
    let hue: GlowHue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.headline)
                    .font(.glow(.headline))
                Spacer(minLength: 8)
                if display.showsCountdown {
                    GlowTimer(display: display)
                        .font(.glow(.headline))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80, alignment: .trailing)
                }
            }
            Text(verbatim: display.codeWord)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(Text("Code word: \(display.codeWord)"))
            if let detail = display.detail {
                Label {
                    Text(detail)
                } icon: {
                    Image(systemName: display.showsCountdown ? "mappin.and.ellipse" : "bubble.left")
                }
                .font(.glow(.callout))
            }
            if display.showsCountdown {
                ProgressView(timerInterval: display.countdown, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(hue.ink.color)
                .accessibilityHidden(true)
            }
        }
        .foregroundStyle(hue.ink.color)
        .padding(16)
    }
}

/// The countdown, as the system draws it: it keeps running while the app sleeps.
struct GlowTimer: View {
    let display: GlowActivityDisplay

    var body: some View {
        Text(timerInterval: display.countdown, countsDown: true)
            .monospacedDigit()
            .accessibilityLabel(Text("Time left"))
    }
}

/// A small disc of the glow color.
struct GlowDot: View {
    let hue: GlowHue
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(hue.color)
            .frame(width: size, height: size)
            .accessibilityLabel(Text("\(hue.name) glow"))
    }
}

#Preview("Lock screen", as: .content, using: GlowActivityAttributes(
    glowID: "453803c0-4199-465b-a12d-1981639daadd",
    color: "aqua",
    codeWord: "lantern",
    meetingSpot: "Water station",
    startedAt: .now,
)) {
    GlowCountdownActivity()
} contentStates: {
    GlowActivityAttributes.ContentState(phase: .glowing, endsAt: .now.addingTimeInterval(900))
    GlowActivityAttributes.ContentState(phase: .theyMet, endsAt: .now.addingTimeInterval(400))
    GlowActivityAttributes.ContentState(phase: .met, endsAt: .now.addingTimeInterval(400))
}
