import PhotosUI
import SwiftUI
import UIKit

// MARK: - Capture

struct CaptureStep: View {
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
