import APIClient
import AppCore
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
        .navigationTitle("Today's look")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeOut(duration: 0.2), value: model.step)
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
            ProgressStep(label: "You're checked in.")
        }
    }
}

// MARK: - Notice

private struct NoticeBanner: View {
    let notice: CheckInModel.Notice
    let onRejoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(CheckInCopy.message(for: notice))
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
            .font(.callout)
            if notice == .roomCheckExpired {
                Button("Back to rooms", action: onRejoin)
                    .font(.callout.weight(.semibold))
                    .accessibilityIdentifier("checkin.rejoin")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("checkin.notice")
    }
}

// MARK: - Progress

struct ProgressStep: View {
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Capture") {
    NavigationStack {
        CheckInView(roomID: RoomID(rawValue: "00000000-0000-4000-8000-000000000001"), ticket: JoinTicket("preview"))
    }
}
