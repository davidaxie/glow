import Foundation

// Owner: C3. What the lock screen and the Dynamic Island say for a glow, worked out without
// WidgetKit so it can be tested. The widget extension only draws this.

/// The words and timer for one moment of a glow's Live Activity.
///
/// The activity ends on time even while the app is asleep: the app sets the activity's stale date
/// to `endsAt`, and once the system marks it stale (or the clock passes `endsAt`) this reads as
/// "Time's up" with no countdown. The app also ends the activity itself when it next runs.
public struct GlowActivityDisplay: Equatable, Sendable {
    /// The code word in capitals, as the glow screen shows it.
    public let codeWord: String
    /// The glow color's contract name, like "aqua".
    public let color: String
    /// The main line: what to do now.
    public let headline: String
    /// Where to go, while the glow is on.
    public let detail: String?
    /// Whether to show the countdown (only while the glow is on).
    public let showsCountdown: Bool
    /// The countdown's interval, for `Text(timerInterval:countsDown:)` and the progress bar.
    public let countdown: ClosedRange<Date>
    /// The phase after the clock is taken into account: a glow past its end reads as expired.
    public let phase: GlowActivityPhase

    public init(
        attributes: GlowActivityAttributes,
        state: GlowActivityAttributes.ContentState,
        now: Date,
        isStale: Bool,
    ) {
        let timeIsUp = isStale || now >= state.endsAt
        let phase: GlowActivityPhase = !state.phase.isOver && timeIsUp ? .expired : state.phase
        self.phase = phase
        codeWord = attributes.codeWord.uppercased()
        color = attributes.color
        showsCountdown = !phase.isOver
        let start = min(attributes.startedAt, state.endsAt)
        countdown = start ... state.endsAt

        switch phase {
        case .glowing: headline = String(localized: "Find each other")
        case .youMet: headline = String(localized: "Waiting for them to tap We met")
        case .theyMet: headline = String(localized: "They tapped We met")
        case .met: headline = String(localized: "You found each other")
        case .canceled: headline = String(localized: "The glow has ended")
        case .expired: headline = String(localized: "Time's up")
        }

        if phase.isOver {
            detail = String(localized: "The chat is still open.")
        } else if let spot = attributes.meetingSpot, !spot.isEmpty {
            detail = String(localized: "Meet at \(spot)")
        } else {
            detail = String(localized: "Look for this color")
        }
    }

    /// How far through the glow `now` is, 0 to 1, for the progress bar.
    public func progress(at now: Date) -> Double {
        let total = countdown.upperBound.timeIntervalSince(countdown.lowerBound)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(countdown.lowerBound) / total, 0), 1)
    }
}
