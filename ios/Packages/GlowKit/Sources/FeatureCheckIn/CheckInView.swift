import APIClient
import AppCore
import DesignSystem
import SwiftUI

/// Outfit photo, blur preview and tags, then upload with the join ticket. The app shows this for
/// `.checkIn(roomID, ticket)` after the location check passes.
public struct CheckInView: View {
    public let roomID: RoomID
    public let ticket: JoinTicket

    @Environment(\.dependencies) private var dependencies

    public init(roomID: RoomID, ticket: JoinTicket) {
        self.roomID = roomID
        self.ticket = ticket
    }

    public var body: some View {
        CheckInScreen(model: CheckInModel(roomID: roomID, ticket: ticket, dependencies: dependencies))
    }
}

/// The flow itself, driven by a `CheckInModel`. Separate from `CheckInView` so tests and
/// previews can hand it a model in any state.
struct CheckInScreen: View {
    @State private var model: CheckInModel
    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: CheckInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.notice {
                NoticeBanner(notice: notice) {
                    navigate(.rooms)
                }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { CheckInCanvas(warmth: CheckInLight.warmth(model.step)) }
        .navigationTitle("Check in")
        .navigationBarTitleDisplayMode(.inline)
        .animation(CheckInLight.motion(CheckInLight.smooth, reduceMotion: reduceMotion), value: model.step)
        .animation(CheckInLight.motion(CheckInLight.gentle, reduceMotion: reduceMotion), value: CheckInLight.warmth(model.step))
        .onChange(of: model.step) { _, step in
            if case .done = step {
                navigate(.roomHome(model.roomID))
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .capture:
            CaptureStep { data in
                Task { await model.photoTaken(data) }
            }
        case .processing:
            ProgressStep(label: "Blurring faces on your phone…")
        case .preview:
            PreviewStep(image: model.previewImage, facesBlurred: model.prepared?.facesBlurred ?? 0) {
                model.confirmPhoto()
            } onRetake: {
                model.retake()
            }
        case .tags, .uploading:
            TagsStep(model: model)
        case .done:
            ProgressStep(label: "You're checked in.", isDone: true)
        }
    }
}

// MARK: - Notice

private struct NoticeBanner: View {
    let notice: CheckInModel.Notice
    let onRejoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            Label {
                Text(CheckInCopy.message(for: notice))
                    .foregroundStyle(Color.glowTextPrimary)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.glowAccent)
            }
            .glowFont(.callout)
            if notice == .roomCheckExpired {
                Button("Back to rooms", action: onRejoin)
                    .buttonStyle(.glow(.quiet, size: .compact))
                    .accessibilityIdentifier("checkin.rejoin")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GlowSpacing.md)
        .background(Color.glowSurfaceRaised, in: RoundedRectangle(cornerRadius: GlowRadius.control))
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.top, GlowSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("checkin.notice")
    }
}

// MARK: - Progress

/// A wait, as a breath of light rather than a spinner; when it's done, the light is full.
struct ProgressStep: View {
    let label: LocalizedStringKey
    var isDone = false

    var body: some View {
        VStack(spacing: GlowSpacing.sm) {
            CheckInBreath(size: isDone ? 240 : 180, intensity: isDone ? 1 : 0.75)
            Text(label)
                .font(CheckInLight.titleSerif)
                .tracking(-0.3)
                .foregroundStyle(isDone ? Color.glowTextPrimary : Color.glowTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, GlowSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Capture") {
    NavigationStack {
        CheckInView(roomID: RoomID(rawValue: "00000000-0000-4000-8000-000000000001"), ticket: JoinTicket("preview"))
    }
}
