import AppCore
import DesignSystem
import SwiftUI
import UIKit

/// The screen between scanning a code and checking in: "Checking you're in the room", then
/// check-in on a pass, or a friendly screen saying what to do next.
public struct JoinFlowView: View {
    public let entry: RoomEntry
    /// Shown while the room's name isn't known yet: the link's slug, or "code".
    private let label: String
    /// When the code was typed on the screen before this one, "Type the code" goes back to it.
    private let onEditCode: (() -> Void)?

    @Environment(\.dependencies) private var dependencies
    @Environment(\.roomJoining) private var roomJoiningOverride
    @Environment(\.navigate) private var navigate
    @State private var model: JoinModel?

    public init(entry: RoomEntry, label: String, onEditCode: (() -> Void)? = nil) {
        self.entry = entry
        self.label = label
        self.onEditCode = onEditCode
    }

    public var body: some View {
        Group {
            if let model {
                JoinStateView(model: model, label: label, onEditCode: onEditCode)
            } else {
                JoinProgressView(title: "Finding the room", caption: "Room: \(label)")
            }
        }
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = JoinModel(
                    entry: entry,
                    service: roomJoiningOverride ?? dependencies.roomJoiningService(),
                    location: dependencies.location,
                    analytics: dependencies.analytics,
                )
            }
            await model?.startIfNeeded()
        }
        .onChange(of: model?.phase) { _, phase in
            if case let .passed(room, ticket, _) = phase {
                navigate(.checkIn(room, ticket))
            }
        }
    }
}

/// Draws the model's phase.
struct JoinStateView: View {
    let model: JoinModel
    let label: String
    let onEditCode: (() -> Void)?

    @Environment(\.navigate) private var navigate
    @Environment(\.openURL) private var openURL

    private var caption: String {
        "Room: \(model.room?.name ?? label)"
    }

    var body: some View {
        JoinStage(
            warmth: warmth,
            isCold: failure != nil,
            symbol: symbol,
            title: title,
            message: message,
            caption: caption,
            identifier: identifier,
        ) {
            switch model.phase {
            case .idle, .resolving, .checking:
                EmptyView()
            case .passed:
                Button("Continue") { continueToCheckIn() }
                    .buttonStyle(.glowPrimary)
                    .shadow(color: Color.glowAccent.opacity(0.35), radius: 18, y: 6)
            case let .failed(failure):
                actionButton(failure.primaryAction, prominent: true)
                if let secondary = failure.secondaryAction {
                    actionButton(secondary, prominent: false)
                }
            }
        }
        .sensoryFeedback(.success, trigger: isPassed)
    }

    // MARK: The room warming up (DIRECTION.md "Joining a room")

    private var failure: JoinFailure? {
        if case let .failed(failure) = model.phase {
            return failure
        }
        return nil
    }

    private var isPassed: Bool {
        if case .passed = model.phase {
            return true
        }
        return false
    }

    /// The light gathers as the join goes: a faint glow while the room is found, warmer while
    /// Glow checks you're inside, full when you're in. A failure cools it to grey.
    private var warmth: Double {
        switch model.phase {
        case .idle, .resolving: 0.25
        case .checking: 0.6
        case .passed: 1
        case .failed: 0.3
        }
    }

    private var symbol: String? {
        switch model.phase {
        case .idle, .resolving, .checking: nil
        case .passed: "checkmark"
        case let .failed(failure): failure.symbol
        }
    }

    private var title: String {
        switch model.phase {
        case .idle, .resolving: "Finding the room"
        case .checking: "Checking you're in the room"
        case .passed: "You're in the room"
        case let .failed(failure): failure.title
        }
    }

    private var message: String? {
        switch model.phase {
        case .idle, .resolving: nil
        case .checking: "Glow checks your location once, then forgets it."
        case .passed: "Next, a quick photo of today's outfit."
        case let .failed(failure): failure.message
        }
    }

    private var identifier: String {
        switch model.phase {
        case .idle, .resolving, .checking: "rooms.join.progress"
        case .passed: "rooms.join.passed"
        case let .failed(failure): "rooms.join.failure.\(failure.name)"
        }
    }

    private func actionButton(_ action: JoinFailure.Action, prominent: Bool) -> some View {
        Button(action.title) { perform(action) }
            .buttonStyle(prominent ? .glowPrimary : .glowSecondary)
    }

    private func perform(_ action: JoinFailure.Action) {
        switch action {
        case .tryAgain:
            Task { await model.retry() }
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .scanAgain:
            navigate(.scanner)
        case .typeCode:
            if let onEditCode {
                onEditCode()
            } else {
                navigate(.roomCode)
            }
        case .backToRooms:
            navigate(.rooms)
        }
    }

    private func continueToCheckIn() {
        if let (room, ticket) = model.liveTicket {
            navigate(.checkIn(room, ticket))
        } else {
            // The ticket ran out while they were away: check again.
            navigate(.rooms)
        }
    }
}

/// A short wait: the room's light, breathing, with a title. No spinner.
struct JoinProgressView: View {
    let title: String
    var message: String?
    let caption: String

    var body: some View {
        JoinStage(
            warmth: 0.25,
            isCold: false,
            symbol: nil,
            title: title,
            message: message,
            caption: caption,
            identifier: "rooms.join.progress",
        ) {
            EmptyView()
        }
    }
}

/// An outcome: a symbol in a cool light, a title, what to do, and buttons.
struct JoinMessageView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    let caption: String
    let identifier: String
    @ViewBuilder let actions: Actions

    var body: some View {
        JoinStage(warmth: 0.3, isCold: true, symbol: symbol, title: title, message: message, caption: caption, identifier: identifier) {
            actions
        }
    }
}

/// One stage of joining: the room's light (one view throughout, so it gathers rather than jumps),
/// a symbol inside it once there's an outcome, a line in New York, what's happening, the room, and
/// the one thing to do under the thumb.
struct JoinStage<Actions: View>: View {
    let warmth: Double
    let isCold: Bool
    let symbol: String?
    let title: String
    let message: String?
    let caption: String
    let identifier: String
    @ViewBuilder let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var lightSize: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(spacing: GlowSpacing.md) {
                ZStack {
                    RoomWarmth(warmth: warmth, size: lightSize, isCold: isCold)
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.glow(.display))
                            .fontWeight(.light)
                            .imageScale(.large)
                            .foregroundStyle(isCold ? AnyShapeStyle(.glowTextSecondary) : AnyShapeStyle(.glowTextPrimary))
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                            .id(symbol)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: lightSize * 0.75)
                VStack(spacing: GlowSpacing.sm) {
                    Text(title)
                        .font(RoomsLight.titleSerif)
                        .tracking(-0.4)
                        .foregroundStyle(.glowTextPrimary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message)
                            .glowFont(.body)
                            .foregroundStyle(.glowTextSecondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    Text(caption)
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, GlowSpacing.xxs)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GlowSpacing.lg)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, GlowSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GlowSpacing.sm) {
                actions
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.bottom, GlowSpacing.sm)
        }
        .background { RoomsCanvas(warmth: isCold ? 0.15 : warmth) }
        .animation(RoomsLight.motion(RoomsLight.smooth, reduceMotion: reduceMotion), value: title)
        .animation(RoomsLight.motion(RoomsLight.smooth, reduceMotion: reduceMotion), value: symbol)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Copy

extension JoinFailure {
    var title: String {
        switch self {
        case .notInRoom: "Not in the room yet"
        case .weakSignal: "Weak signal"
        case .roomEnded, .roomClosed: "This room has ended"
        case .roomPaused: "This room is paused"
        case let .roomNotOpenYet(date): "This room opens at \(date.formatted(date: .omitted, time: .shortened))"
        case .roomNotFound: "We couldn't find that room"
        case .codeChanged: "That code changed"
        case .locationDenied: "Location is off for Glow"
        case .preciseLocationOff: "Precise location is off"
        case .locationUnavailable: "Location Services are off"
        case .onboardingIncomplete: "Finish your profile first"
        case .offline: "You're offline"
        case .rateLimited: "Slow down a little"
        case .unexpected: "Something went wrong"
        }
    }

    var message: String {
        switch self {
        case .notInRoom:
            "Looks like you're not in this room yet. Try again inside."
        case .weakSignal:
            "Your location isn't clear enough right now. Try near a window or door, then try again."
        case .roomEnded, .roomClosed:
            "Thanks for coming. To join another room, scan its code."
        case .roomPaused:
            "The host paused this room for a moment. Try again in a little while."
        case .roomNotOpenYet:
            "Come back then and scan the code again."
        case .roomNotFound:
            "Check the code and try again, or scan the room's QR code."
        case .codeChanged:
            "The code on the screen changes every 30 seconds. Scan it again."
        case .locationDenied:
            "Glow checks once that you're inside the room, then forgets your location. Turn on location for Glow in Settings."
        case .preciseLocationOff:
            "Glow needs your precise location once to confirm you're inside this room. It isn't stored."
        case .locationUnavailable:
            "Turn on Location Services in Settings, then try again."
        case .onboardingIncomplete:
            "Rooms open once your profile is set up."
        case .offline:
            "Check your connection, then try again."
        case .rateLimited:
            "Wait a minute, then try again."
        case .unexpected:
            "Try again in a moment."
        }
    }

    var symbol: String {
        switch self {
        case .notInRoom: "location.slash"
        case .weakSignal: "antenna.radiowaves.left.and.right.slash"
        case .roomEnded, .roomClosed: "moon.stars"
        case .roomPaused: "pause.circle"
        case .roomNotOpenYet: "clock"
        case .roomNotFound: "questionmark.circle"
        case .codeChanged: "qrcode.viewfinder"
        case .locationDenied, .preciseLocationOff, .locationUnavailable: "location.circle"
        case .onboardingIncomplete: "person.crop.circle"
        case .offline: "wifi.slash"
        case .rateLimited: "hourglass"
        case .unexpected: "exclamationmark.circle"
        }
    }

    var secondaryAction: Action? {
        switch self {
        case .notInRoom, .weakSignal, .preciseLocationOff: .backToRooms
        case .roomNotFound: .scanAgain
        case .codeChanged: .typeCode
        case .locationDenied: .backToRooms
        default: nil
        }
    }
}

extension JoinFailure.Action {
    var title: String {
        switch self {
        case .tryAgain: "Try again"
        case .openSettings: "Open Settings"
        case .scanAgain: "Scan the code"
        case .typeCode: "Type the room code"
        case .backToRooms: "Back to Rooms"
        }
    }
}
