import AVFoundation
import DesignSystem
import os
import SwiftUI
import UIKit

/// One still photo from the camera with AVFoundation, held in memory only. The photo is never
/// saved to the library or to disk, and the pipeline strips its metadata before anything else
/// sees it.
final class CameraController: NSObject, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case denied
        case unavailable
        case captureFailed
    }

    // Everything below is touched only on `queue`, except `session` for the preview layer.
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.davidxie.glow.camera")
    private var configured = false
    private var position: AVCaptureDevice.Position = .back
    private let pending = OSAllocatedUnfairLock<CheckedContinuation<Data, any Error>?>(initialState: nil)

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() async throws(Failure) {
        guard await Self.requestAccess() else { throw .denied }
        let ok: Bool = await withCheckedContinuation { continuation in
            queue.async {
                let ready = self.configureIfNeeded()
                if ready, !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume(returning: ready)
            }
        }
        guard ok else { throw .unavailable }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func flip() {
        queue.async {
            self.position = self.position == .back ? .front : .back
            self.configured = false
            _ = self.configureIfNeeded()
        }
    }

    /// Takes one JPEG still. Its bytes stay in memory.
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            pending.withLock { $0 = continuation }
            queue.async {
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.photoQualityPrioritization = .balanced
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured {
            return true
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        for input in session.inputs {
            session.removeInput(input)
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }
        configured = true
        return true
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let continuation = pending.withLock { value in
            defer { value = nil }
            return value
        }
        if error == nil, let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: Failure.captureFailed)
        }
    }
}

/// The live camera preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// The neck-down framing guide drawn over the camera: a line where the neck should be, and the
/// outline of a torso below it. Faces stay out of frame; the blur catches any that don't.
struct FramingGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let neckY = size.height * 0.12
            ZStack(alignment: .top) {
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.08, y: neckY))
                    path.addLine(to: CGPoint(x: size.width * 0.92, y: neckY))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(Color.glowTextPrimary.opacity(0.85))

                RoundedRectangle(cornerRadius: 28)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(Color.glowTextPrimary.opacity(0.6))
                    .frame(width: size.width * 0.7, height: size.height * 0.78)
                    .offset(y: neckY + size.height * 0.04)

                Text("Neck here")
                    .glowFont(.caption)
                    .foregroundStyle(Color.glowTextPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.glowBackground.opacity(0.6), in: Capsule())
                    .offset(y: max(0, neckY - 30))
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
