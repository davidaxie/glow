import APIClient
import AppCore
import PhotosUI
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

// MARK: - Capture

private struct CaptureStep: View {
    let onPhoto: (Data) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Take a quick photo of today's outfit, from the neck down. Faces are blurred on your phone before anything is sent.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            #if DEBUG && targetEnvironment(simulator)
                LibraryPicker(onPhoto: onPhoto)
            #else
                CameraStep(onPhoto: onPhoto)
            #endif
        }
    }
}

/// Debug Simulator builds only: the Simulator has no camera, so pick a fixture photo instead.
private struct LibraryPicker: View {
    let onPhoto: (Data) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.quaternary)
                FramingGuide().padding(24)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .padding(.horizontal, 32)

            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("checkin.choosePhoto")
            Spacer(minLength: 0)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                item = nil
                if let data { onPhoto(data) }
            }
        }
    }
}

private struct CameraStep: View {
    let onPhoto: (Data) -> Void
    @State private var camera = CameraController()
    @State private var failure: CameraController.Failure?
    @State private var capturing = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                if failure == nil {
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    FramingGuide().padding(24)
                } else {
                    RoundedRectangle(cornerRadius: 20).fill(.quaternary)
                    VStack(spacing: 12) {
                        Text(failure == .denied
                            ? "Glow needs the camera for your outfit photo. Nothing is saved to your library."
                            : "The camera isn't available right now.")
                            .multilineTextAlignment(.center)
                        if failure == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Camera. Frame your outfit from the neck down."))

            HStack(spacing: 40) {
                Button {
                    camera.flip()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Switch camera"))

                Button {
                    Task { await shoot() }
                } label: {
                    Circle()
                        .strokeBorder(.primary, lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().fill(.primary).padding(8))
                }
                .disabled(capturing || failure != nil)
                .accessibilityLabel(Text("Take photo"))
                .accessibilityIdentifier("checkin.shutter")

                Color.clear.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
        }
        .task {
            do {
                try await camera.start()
            } catch {
                failure = (error as? CameraController.Failure) ?? .unavailable
            }
        }
        .onDisappear { camera.stop() }
    }

    private func shoot() async {
        capturing = true
        defer { capturing = false }
        do {
            let data = try await camera.capture()
            onPhoto(data)
        } catch {
            failure = .captureFailed
        }
    }
}

// MARK: - Progress

private struct ProgressStep: View {
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

private struct PreviewStep: View {
    let image: UIImage?
    let facesBlurred: Int
    let onConfirm: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("This is what others will see")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .frame(maxHeight: 460)
                        .accessibilityLabel(Text(facesBlurred > 0
                                ? "Your outfit photo, with faces blurred"
                                : "Your outfit photo"))
                        .accessibilityIgnoresInvertColors()
                }
                Text(facesBlurred > 0
                    ? "Faces are blurred. Your original photo never leaves your phone."
                    : "No faces found. Your original photo never leaves your phone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text("Use this photo").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("checkin.usePhoto")
                    Button(action: onRetake) {
                        Text("Retake").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("checkin.retake")
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Tags

private struct TagsStep: View {
    @Bindable var model: CheckInModel

    private var uploading: Bool {
        model.step == .uploading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if let image = model.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A few details")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("They help the person who noticed you find your card.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                TagSection(title: "Top color", subtitle: "Required") {
                    ForEach(Components.Schemas.TopColor.allCases, id: \.self) { color in
                        Chip(
                            title: CheckInCopy.name(color),
                            swatch: TopColorSwatch.color(color),
                            selected: model.tags.topColor == color,
                        ) {
                            model.tags.topColor = color
                        }
                        .accessibilityIdentifier("checkin.top.\(color.rawValue)")
                    }
                }

                TagSection(title: "Hair length", subtitle: "Optional") {
                    ForEach(Components.Schemas.HairLength.allCases, id: \.self) { length in
                        Chip(title: CheckInCopy.name(length), selected: model.tags.hairLength == length) {
                            model.tags.hairLength = model.tags.hairLength == length ? nil : length
                        }
                    }
                }

                TagSection(title: "Hair color", subtitle: "Optional") {
                    ForEach(Components.Schemas.HairColor.allCases, id: \.self) { color in
                        Chip(title: CheckInCopy.name(color), selected: model.tags.hairColor == color) {
                            model.tags.hairColor = model.tags.hairColor == color ? nil : color
                        }
                    }
                }

                TagSection(title: "Anything else", subtitle: "Pick any") {
                    ForEach(Components.Schemas.CardExtra.allCases, id: \.self) { extra in
                        Chip(title: CheckInCopy.name(extra), selected: model.tags.extras.contains(extra)) {
                            if model.tags.extras.contains(extra) {
                                model.tags.extras.remove(extra)
                            } else {
                                model.tags.extras.insert(extra)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        Group {
                            if uploading {
                                ProgressView()
                            } else {
                                Text("Check in")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
                    .accessibilityLabel(Text(uploading ? "Checking in" : "Check in"))
                    .accessibilityIdentifier("checkin.submit")

                    Button {
                        model.backToPreview()
                    } label: {
                        Text("Back to photo").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(uploading)
                }
            }
            .padding(24)
            .disabled(uploading)
        }
    }
}

private struct TagSection<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                content
            }
        }
    }
}

private struct Chip: View {
    let title: LocalizedStringKey
    var swatch: Color?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1))
                        .frame(width: 16, height: 16)
                }
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Lays chips out in rows that wrap, so every option fits at any text size.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let fitted = CGSize(width: min(size.width, bounds.width), height: size.height)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(fitted))
                x += fitted.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview("Capture") {
    NavigationStack {
        CheckInView(roomID: RoomID(rawValue: "00000000-0000-4000-8000-000000000001"), ticket: JoinTicket("preview"))
    }
}
