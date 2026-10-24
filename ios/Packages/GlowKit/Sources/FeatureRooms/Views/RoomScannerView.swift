@preconcurrency import AVFoundation
import AppCore
import SwiftUI
import UIKit

/// The in-app QR scanner, for people who open Glow first. A room's code opens the join flow;
/// anything else is ignored with a short note. Torch button for dark venues, and the typed
/// room code as a fallback.
public struct RoomScannerView: View {
    enum CameraState: Equatable {
        case starting
        case denied
        case noCamera
        case scanning(hasTorch: Bool)
    }

    @Environment(\.dependencies) private var dependencies
    @Environment(\.navigate) private var navigate
    @Environment(\.openURL) private var openURL
    @State private var camera = QRCaptureSession()
    @State private var state: CameraState = .starting
    @State private var torchOn = false
    @State private var notGlow = false
    @State private var found = 0
    @State private var lastIgnored: String?

    public init() {}

    public var body: some View {
        content
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .task { await prepare() }
            .onDisappear {
                camera.stop()
                torchOn = false
            }
            .sensoryFeedback(.success, trigger: found)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .starting:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Starting the camera")
        case .denied:
            JoinMessageView(
                symbol: "camera",
                title: "Camera is off for Glow",
                message: "Turn on the camera for Glow in Settings to scan room codes, or type the room's code instead.",
                caption: "Glow only looks for room codes. Nothing is recorded.",
                identifier: "rooms.scanner.denied",
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                typeCodeButton
            }
        case .noCamera:
            JoinMessageView(
                symbol: "camera",
                title: "No camera here",
                message: "This device can't scan codes. Type the room's code instead.",
                caption: "Or scan the room's QR code with another iPhone's camera app.",
                identifier: "rooms.scanner.no_camera",
            ) {
                typeCodeButton
            }
        case let .scanning(hasTorch):
            scanner(hasTorch: hasTorch)
        }
    }

    private func scanner(hasTorch: Bool) -> some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(notGlow ? "That isn't a Glow room code." : "Point at the room's QR code")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("rooms.scanner.hint")
                Spacer()
                HStack(spacing: 12) {
                    if hasTorch {
                        Button {
                            torchOn.toggle()
                            camera.setTorch(torchOn)
                        } label: {
                            Label(torchOn ? "Torch on" : "Torch off", systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel("Torch")
                        .accessibilityValue(torchOn ? "On" : "Off")
                        .accessibilityIdentifier("rooms.scanner.torch")
                    }
                    typeCodeButton
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 16)
        }
        .accessibilityIdentifier("rooms.scanner")
    }

    private var typeCodeButton: some View {
        Button {
            navigate(.roomCode)
        } label: {
            Label("Type the code", systemImage: "keyboard")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("rooms.scanner.type_code")
    }

    private func prepare() async {
        guard state == .starting else {
            camera.start()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        camera.setHandler { code in handle(code) }
        switch await camera.configure() {
        case .noCamera:
            state = .noCamera
        case let .ready(hasTorch):
            state = .scanning(hasTorch: hasTorch)
            camera.start()
        }
    }

    private func handle(_ code: String) {
        if let url = URL(string: code), case let .joinRoom(link) = DeepLink.route(for: url, config: dependencies.config) {
            camera.stop()
            found += 1
            dependencies.analytics.track(AnalyticsEvent("room_code_scanned", ["glow": true]))
            navigate(.joinRoom(link))
            return
        }
        guard code != lastIgnored else { return }
        // Never logged or kept: a scanned code could be anything.
        lastIgnored = code
        notGlow = true
        dependencies.analytics.track(AnalyticsEvent("room_code_scanned", ["glow": false]))
        Task {
            try? await Task.sleep(for: .seconds(2))
            notGlow = false
        }
    }
}
