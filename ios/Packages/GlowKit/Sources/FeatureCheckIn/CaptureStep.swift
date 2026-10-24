import DesignSystem
import PhotosUI
import SwiftUI
import UIKit

/// Step 1: today's outfit, from the neck down. The camera on a phone; the photo picker in Debug
/// Simulator builds, which have no camera.
struct CaptureStep: View {
    let onPhoto: (Data) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: GlowSpacing.lg) {
                GlowStepHeader(
                    step: 1,
                    of: 3,
                    title: "Today's look",
                    subtitle: "A quick photo of your outfit, from the neck down. Faces are blurred on your phone before anything is sent.",
                )
                #if DEBUG && targetEnvironment(simulator)
                    LibraryPicker(onPhoto: onPhoto)
                #else
                    CameraStep(onPhoto: onPhoto)
                #endif
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.md)
        }
    }
}

/// Debug Simulator builds only: the Simulator has no camera, so pick a fixture photo instead.
private struct LibraryPicker: View {
    let onPhoto: (Data) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: GlowRadius.card).fill(Color.glowSurface)
                FramingGuide().padding(GlowSpacing.lg)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: 260)

            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                Label("Choose a photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.glowPrimary)
            .accessibilityIdentifier("checkin.choosePhoto")

            // UI tests launch with `-GlowDebugCheckInPhoto <path to a fixture>` to skip the
            // system photo picker, which runs out of process.
            if let path = UserDefaults.standard.string(forKey: "GlowDebugCheckInPhoto") {
                Button("Use test photo") {
                    if let data = FileManager.default.contents(atPath: path) {
                        onPhoto(data)
                    }
                }
                .buttonStyle(.glowSecondary)
                .accessibilityIdentifier("checkin.debugPhoto")
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                item = nil
                if let data {
                    onPhoto(data)
                }
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
        VStack(spacing: GlowSpacing.lg) {
            ZStack {
                if failure == nil {
                    CameraPreview(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card))
                    FramingGuide().padding(GlowSpacing.lg)
                } else {
                    RoundedRectangle(cornerRadius: GlowRadius.card).fill(Color.glowSurface)
                    VStack(spacing: GlowSpacing.sm) {
                        Text(failure == .denied
                            ? "Glow needs the camera for your outfit photo. Nothing is saved to your library."
                            : "The camera isn't available right now.")
                            .glowFont(.body)
                            .foregroundStyle(Color.glowTextPrimary)
                            .multilineTextAlignment(.center)
                        if failure == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.glow(.secondary, size: .compact))
                        }
                    }
                    .padding(GlowSpacing.lg)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: 260)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Camera. Frame your outfit from the neck down."))

            HStack(spacing: GlowSpacing.xl) {
                Button {
                    camera.flip()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .glowFont(.headline)
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                }
                .foregroundStyle(Color.glowTextPrimary)
                .accessibilityLabel(Text("Switch camera"))

                Button {
                    Task { await shoot() }
                } label: {
                    Circle()
                        .strokeBorder(Color.glowTextPrimary, lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().fill(Color.glowTextPrimary).padding(GlowSpacing.xs))
                }
                .disabled(capturing || failure != nil)
                .accessibilityLabel(Text("Take photo"))
                .accessibilityIdentifier("checkin.shutter")

                Spacer().frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
            }
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
