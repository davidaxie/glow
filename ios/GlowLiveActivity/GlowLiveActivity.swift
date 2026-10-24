import ActivityKit
import LiveActivityShared
import SwiftUI
import WidgetKit

// Placeholder from A3 so the extension builds on day one. Owner: C3.
// The lock screen and Dynamic Island views for the glow countdown. Never shows a name (P6).

@main
struct GlowLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        GlowCountdownActivity()
    }
}

struct GlowCountdownActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlowActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.codeWord)
                    .font(.title2.bold())
                Text(context.attributes.meetingSpot)
                    .font(.subheadline)
                Text(timerInterval: Date.now ... context.state.endsAt, countsDown: true)
                    .monospacedDigit()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.codeWord).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.meetingSpot)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text(timerInterval: Date.now ... context.state.endsAt, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}
