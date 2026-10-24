import APIClient
import AppCore
import DesignSystem
import PhotosUI
import Session
import SwiftUI

/// Step 2 of 3: 1 to 3 profile photos. Each is cropped to 4:5 and stripped of its metadata on
/// the phone, then moderated on the server. Only approved ones count, and only matches see them.
struct PhotosStepView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var slots = PhotoSlots()
    @State private var isContinuing = false

    private var client: ProfileClient {
        ProfileClient(api: dependencies.api, session: dependencies.session)
    }

    var body: some View {
        OnboardingScreen {
            PhotosStepContent(slots: slots) { data, position in
                await slots.add(data, at: position, using: client)
            } remove: { position in
                await slots.remove(at: position, using: client)
            }
        } actions: {
            Button("Continue") {
                Task { await next() }
            }
            .buttonStyle(.glowPrimary)
            .disabled(!slots.isEnough)
            .accessibilityIdentifier("photos.continue")
        }
        .glowLoading(isContinuing)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("onboarding.photos")
        .task {
            if let photos = await dependencies.session.currentProfile()?.photos {
                slots.show(photos)
            }
            await slots.loadImages(using: client)
        }
    }

    /// The server already moved the step on when the first photo was approved; fetching the
    /// profile moves the app with it.
    private func next() async {
        isContinuing = true
        defer { isContinuing = false }
        do {
            try await dependencies.session.refreshProfile()
            dependencies.analytics.track(AnalyticsEvent("onboarding_step_done", ["step": "photos", "photos": .int(slots.approvedCount)]))
        } catch {
            slots.error = (error as? APIError).map(ProfileClient.error(from:)) ?? .unexpected
        }
    }
}

struct PhotosStepContent: View {
    let slots: PhotoSlots
    let add: (Data, Int) async -> Void
    let remove: (Int) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            GlowStepHeader(
                step: 2,
                of: OnboardingProgress.steps,
                title: "Add your photos",
                subtitle: "1 to 3 photos of you. Only people you match with ever see them.",
            )
            PhotoGrid(slots: slots, add: add, remove: remove)
            if slots.hasHeld {
                InlineMessage(
                    text: Text("A person at Glow will look at any photo marked \"Being checked\". Until then nobody sees it."),
                    isError: false,
                )
            }
            if let error = slots.error {
                InlineMessage(text: Text(error.message))
            }
            Text("Glow removes the location and camera details from every photo before it leaves your phone.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Three 4:5 photo tiles. Tap an empty one to add a photo, a filled one to replace it.
struct PhotoGrid: View {
    let slots: PhotoSlots
    let add: (Data, Int) async -> Void
    let remove: (Int) async -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? PhotoTilesLayout(columns: 2, spacing: GlowSpacing.sm)
            : PhotoTilesLayout(columns: 3, spacing: GlowSpacing.sm)
        layout {
            ForEach(slots.slots) { slot in
                PhotoTile(slot: slot, add: add, remove: remove)
            }
        }
    }
}

struct PhotoTile: View {
    let slot: PhotoSlots.Slot
    let add: (Data, Int) async -> Void
    let remove: (Int) async -> Void

    @State private var pick: PhotosPickerItem?
    @State private var isPicking = false

    private var number: Int {
        slot.position + 1
    }

    var body: some View {
        Button {
            isPicking = true
        } label: {
            tile
        }
        .buttonStyle(.plain)
        .photosPicker(isPresented: $isPicking, selection: $pick, matching: .images, preferredItemEncoding: .compatible)
        .disabled(slot.status == .uploading)
        .overlay(alignment: .topTrailing) {
            if slot.photoID != nil, slot.status != .uploading {
                Button {
                    Task { await remove(slot.position) }
                } label: {
                    Image(systemName: "xmark")
                        .glowFont(.caption)
                        .foregroundStyle(.glowTextPrimary)
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                        .background(Color.glowSurfaceRaised.opacity(0.9), in: Circle().inset(by: 8))
                }
                .accessibilityLabel(Text("Remove photo \(number)"))
                .accessibilityIdentifier("photos.remove.\(slot.position)")
            }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                // The picked photo stays in memory only, and only until it's prepared.
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await add(data, slot.position)
                }
                pick = nil
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: GlowRadius.card)
            .fill(.glowSurface)
            .overlay {
                if let data = slot.image, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "plus")
                        .glowFont(.title)
                        .foregroundStyle(.glowAccent)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                badge
            }
            .overlay {
                if slot.status == .uploading {
                    ProgressView()
                        .tint(.glowTextPrimary)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card))
            .overlay(RoundedRectangle(cornerRadius: GlowRadius.card).strokeBorder(.glowLine))
            .contentShape(RoundedRectangle(cornerRadius: GlowRadius.card))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHint(slot.photoID == nil ? Text("Opens your photos") : Text("Choose a photo to replace it"))
            .accessibilityIdentifier("photos.slot.\(slot.position)")
    }

    @ViewBuilder private var badge: some View {
        if slot.status == .held {
            Text("Being checked")
                .glowFont(.caption)
                .foregroundStyle(.glowTextPrimary)
                .padding(.horizontal, GlowSpacing.xs)
                .padding(.vertical, GlowSpacing.xxs)
                .background(.glowSurfaceRaised, in: Capsule())
                .padding(GlowSpacing.xs)
                .accessibilityHidden(true)
        }
    }

    private var label: Text {
        switch slot.status {
        case .empty: Text("Add photo \(number)")
        case .uploading: Text("Photo \(number), uploading")
        case .approved: Text("Photo \(number)")
        case .held: Text("Photo \(number), being checked")
        }
    }
}
