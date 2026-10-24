import APIClient
import AppCore
import DesignSystem
import PhotosUI
import Session
import SwiftUI

/// Settings → Edit photos: add, replace or remove. A finished profile always keeps at least one
/// approved photo (the server answers 409 `last_photo` otherwise).
public struct EditPhotosView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var slots = PhotoSlots()

    public init() {}

    private var client: ProfileClient {
        ProfileClient(api: dependencies.api, session: dependencies.session)
    }

    public var body: some View {
        ScrollView {
            EditPhotosContent(slots: slots) { data, position in
                await slots.add(data, at: position, using: client)
                _ = try? await dependencies.session.refreshProfile()
            } remove: { position in
                await slots.remove(at: position, using: client)
                _ = try? await dependencies.session.refreshProfile()
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.lg)
        }
        .background(.glowBackground)
        .navigationTitle("Edit photos")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.editPhotosScreen")
        .task {
            if let photos = await dependencies.session.currentProfile()?.photos {
                slots.show(photos)
            }
            await slots.loadImages(using: client)
        }
    }
}

struct EditPhotosContent: View {
    let slots: PhotoSlots
    let add: (Data, Int) async -> Void
    let remove: (Int) async -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            Text("1 to 3 photos of you. Only people you match with ever see them, and only approved ones.")
                .glowFont(.callout)
                .foregroundStyle(.glowTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: GlowSpacing.sm))
                : AnyLayout(HStackLayout(spacing: GlowSpacing.sm))
            layout {
                ForEach(slots.slots) { slot in
                    SettingsPhotoTile(slot: slot, add: add, remove: remove)
                }
            }
            if slots.hasHeld {
                SettingsMessage(
                    text: Text("A person at Glow will look at the photo marked \"Being checked\". Until then nobody sees it."),
                    isError: false,
                )
            }
            if let error = slots.error {
                SettingsMessage(text: Text(error.settingsMessage))
            }
        }
    }
}

struct SettingsPhotoTile: View {
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
            removeButton
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await add(data, slot.position)
                }
                pick = nil
            }
        }
        .accessibilityIdentifier("editPhotos.slot.\(slot.position)")
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: GlowRadius.card)
            .fill(.glowSurface)
            .overlay {
                if let data = slot.image, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().accessibilityHidden(true)
                } else {
                    Image(systemName: "plus")
                        .glowFont(.title)
                        .foregroundStyle(.glowAccent)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
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
            .overlay {
                if slot.status == .uploading {
                    ProgressView().tint(.glowTextPrimary).accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card))
            .overlay(RoundedRectangle(cornerRadius: GlowRadius.card).strokeBorder(.glowLine))
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: GlowRadius.card))
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    @ViewBuilder private var removeButton: some View {
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
            .accessibilityIdentifier("editPhotos.remove.\(slot.position)")
        }
    }

    private var label: Text {
        switch slot.status {
        case .empty: Text("Add photo \(number)")
        case .uploading: Text("Photo \(number), uploading")
        case .approved: Text("Photo \(number). Choose a photo to replace it.")
        case .held: Text("Photo \(number), being checked")
        }
    }
}
