import AppCore
@preconcurrency import AVFoundation
import os
import SwiftUI
import UIKit

/// The camera side of the in-app scanner: an AVCaptureSession that only looks for QR codes.
///
/// Nothing is recorded or saved: frames go to the metadata detector and the on-screen preview,
/// nowhere else. Every session change runs on one serial queue, because `startRunning` blocks.
final class QRCaptureSession: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum Setup: Sendable, Equatable {
        case ready(hasTorch: Bool)
        case noCamera
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "glow.rooms.scanner")
    private let logger = Logger(subsystem: Log.subsystem, category: "rooms.scanner")
    // Only touched on `queue`.
    private var device: AVCaptureDevice?
    private var configured = false
    // Only touched on the main thread.
    private var onCode: (@MainActor (String) -> Void)?

    @MainActor
    func setHandler(_ handler: @escaping @MainActor (String) -> Void) {
        onCode = handler
    }

    /// Adds the back camera and a QR detector. Safe to call more than once.
    func configure() async -> Setup {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: configureOnQueue())
            }
        }
    }

    private func configureOnQueue() -> Setup {
        if configured, let device {
            return .ready(hasTorch: device.hasTorch)
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera)
        else {
            return .noCamera
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return .noCamera }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return .noCamera }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        device = camera
        configured = true
        return .ready(hasTorch: camera.hasTorch)
    }

    func start() {
        queue.async { [self] in
            if configured, !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            setTorchOnQueue(false)
        }
    }

    func setTorch(_ on: Bool) {
        queue.async { [self] in setTorchOnQueue(on) }
    }

    private func setTorchOnQueue(_ on: Bool) {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            logger.notice("Couldn't change the torch")
        }
    }

    // Delivered on the main queue (see `setMetadataObjectsDelegate`).
    func metadataOutput(
        _: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from _: AVCaptureConnection,
    ) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard let code = codes.first else { return }
        MainActor.assumeIsolated {
            onCode?(code)
        }
    }
}

/// The live camera picture behind the scanner.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }
}
