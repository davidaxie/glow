import ActivityKit
import Foundation
import LiveActivityShared
import os

// Owner: C3. Starting, updating and ending the glow's Live Activity (spec: "A Live Activity on the
// lock screen counts down 15 minutes").

/// The glow's lock screen and Dynamic Island countdown. A protocol so the glow screen can be
/// tested without ActivityKit.
@MainActor
public protocol GlowLiveActivities: AnyObject {
    /// Starts the activity for this glow, or updates it if it's already showing.
    func show(_ session: GlowSession, at now: Date) async
    /// Ends this glow's activity, showing how it ended for a moment first.
    func end(_ session: GlowSession, at now: Date) async
    /// Ends every glow activity whose time has run out, and any for a glow other than `keeping`.
    func endFinished(at now: Date, keeping glowID: String?) async
}

/// ActivityKit. Works in the Simulator too.
///
/// - The activity's stale date is the glow's end, so the lock screen reads "Time's up" on time
///   even if the app is asleep (`GlowActivityDisplay`).
/// - Only one glow shows at a time: starting one ends any other.
/// - An ended glow leaves the lock screen `lingerAfterEnd` later (C3-D4): long enough to read how
///   it ended, short enough that the code word doesn't sit on the lock screen.
@MainActor
public final class ActivityKitGlowLiveActivities: GlowLiveActivities {
    public static let lingerAfterEnd: TimeInterval = 60

    public init() {}

    public func show(_ session: GlowSession, at now: Date) async {
        let content = ActivityContent(
            state: session.activityState(at: now),
            staleDate: session.endsAt,
            relevanceScore: 100,
        )
        if await Self.update(glowID: session.id, to: content) {
            return
        }
        await Self.endAll(at: now, keeping: nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.logger.info("Live Activities are off; the glow screen still counts down")
            return
        }
        do {
            _ = try Activity.request(attributes: session.activityAttributes, content: content, pushType: nil)
        } catch {
            // Too many activities, or the person turned them off mid-glow. The screen still works.
            Self.logger.error("Couldn't start the glow's Live Activity")
        }
    }

    public func end(_ session: GlowSession, at now: Date) async {
        let content = ActivityContent(state: session.activityState(at: now), staleDate: nil)
        await Self.end(glowID: session.id, with: content, dismissAt: now.addingTimeInterval(Self.lingerAfterEnd))
    }

    public func endFinished(at now: Date, keeping glowID: String?) async {
        await Self.endAll(at: now, keeping: glowID)
    }

    // ActivityKit's `Activity` isn't Sendable, so it never crosses to the main actor: each helper
    // looks the activities up and talks to them in its own nonisolated context.

    private nonisolated static let logger = Logger(subsystem: "com.davidxie.glow", category: "glow.activity")

    /// Updates this glow's activity. False if there isn't one.
    private nonisolated static func update(
        glowID: String,
        to content: ActivityContent<GlowActivityAttributes.ContentState>,
    ) async -> Bool {
        var found = false
        for activity in Activity<GlowActivityAttributes>.activities where activity.attributes.glowID == glowID {
            found = true
            await activity.update(content)
        }
        return found
    }

    private nonisolated static func end(
        glowID: String,
        with content: ActivityContent<GlowActivityAttributes.ContentState>,
        dismissAt date: Date,
    ) async {
        for activity in Activity<GlowActivityAttributes>.activities where activity.attributes.glowID == glowID {
            await activity.end(content, dismissalPolicy: .after(date))
        }
    }

    /// Ends, at once, every glow activity that isn't `keeping` or whose time has run out.
    private nonisolated static func endAll(at now: Date, keeping glowID: String?) async {
        for activity in Activity<GlowActivityAttributes>.activities
            where activity.attributes.glowID != glowID || activity.content.state.endsAt <= now
        {
            var state = activity.content.state
            if !state.phase.isOver {
                state.phase = .expired
            }
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
