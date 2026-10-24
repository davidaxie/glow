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
        switch model.phase {
        case .idle, .resolving:
            JoinProgressView(title: "Finding the room", caption: caption)
        case .checking:
            JoinProgressView(
                title: "Checking you're in the room",
                message: "Glow checks your location once, then forgets it.",
                caption: caption,
            )
        case .passed:
            JoinMessageView(
                symbol: "checkmark.circle",
                title: "You're in the room",
                message: "Next, a quick photo of today's outfit.",
                caption: caption,
                identifier: "rooms.join.passed",
            ) {
                Button("Continue") { continueToCheckIn() }
                    .buttonStyle(.glowPrimary)
            }
        case let .failed(failure):
            JoinMessageView(
                symbol: failure.symbol,
                title: failure.title,
                message: failure.message,
                caption: caption,
                identifier: "rooms.join.failure.\(failure.name)",
            ) {
                actionButton(failure.primaryAction, prominent: true)
                if let secondary = failure.secondaryAction {
                    actionButton(secondary, prominent: false)
                }
            }
        }
    }

    @ViewBuilder
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

/// A spinner with a title, for the short waits.
struct JoinProgressView: View {
    let title: String
    var message: String?
    let caption: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.glowAccent)
                    .padding(.bottom, 8)
                Text(title)
                    .glowFont(.title)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .glowFont(.body)
                        .foregroundStyle(.glowTextSecondary)
                        .multilineTextAlignment(.center)
                }
                Text(caption)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.top, 80)
        }
        .accessibilityIdentifier("rooms.join.progress")
    }
}

/// An outcome: a symbol, a title, what to do, and buttons.
struct JoinMessageView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    let caption: String
    let identifier: String
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .glowFont(.display)
                    .imageScale(.large)
                    .foregroundStyle(.glowAccent)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text(title)
                    .glowFont(.title)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)
                    .multilineTextAlignment(.center)
                Text(caption)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                VStack(spacing: 12) {
                    actions
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.top, 48)
        }
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
