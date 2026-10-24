import AppCore
import DesignSystem
import SwiftUI

// Owner: B2. The app shows these for `.rooms`, `.scanner`, `.roomCode` and `.joinRoom`; keep these
// public initializers (ios/Glow/Navigation/RouteDestination.swift calls them).

/// The Rooms tab: scan a room's QR code, or type its code.
public struct RoomsHomeView: View {
    static let intro = "Scan the room's QR code with your iPhone camera or here. "
        + "Glow checks once that you're inside, then forgets your location."

    @Environment(\.navigate) private var navigate

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "qrcode.viewfinder")
                    .glowFont(.display)
                    .imageScale(.large)
                    .foregroundStyle(.glowAccent)
                    .padding(.top, 48)
                    .accessibilityHidden(true)
                Text("Join a room")
                    .glowFont(.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.intro)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button {
                        navigate(.scanner)
                    } label: {
                        Label("Scan a room code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glowPrimary)
                    .accessibilityIdentifier("rooms.home.scan")

                    Button {
                        navigate(.roomCode)
                    } label: {
                        Label("Type a room code", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glowSecondary)
                    .accessibilityIdentifier("rooms.home.code")
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
        .navigationTitle("Rooms")
        .accessibilityIdentifier("screen.FeatureRooms.home")
    }
}

/// Type a room's 6-character code, then the same join flow as a scan.
public struct RoomCodeEntryView: View {
    private let note: String?
    @State private var code = ""
    @State private var submitted: String?
    @FocusState private var focused: Bool

    public init() {
        note = nil
    }

    /// For a room link that came without a token: the person types the code instead.
    init(note: String) {
        self.note = note
    }

    public var body: some View {
        if let submitted {
            JoinFlowView(entry: .code(submitted), label: submitted) {
                self.submitted = nil
                focused = true
            }
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Type the room code")
                    .glowFont(.title)
                    .accessibilityAddTraits(.isHeader)
                Text(note ?? "It's the \(RoomCode.length)-character code on the room's poster or screen.")
                    .foregroundStyle(.glowTextSecondary)
                TextField("Room code", text: $code)
                    .glowFont(.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.join)
                    .focused($focused)
                    .padding(12)
                    .background(.glowSurfaceRaised, in: RoundedRectangle(cornerRadius: GlowRadius.control))
                    .onChange(of: code) { _, newValue in
                        let normalized = RoomCode.normalize(newValue)
                        if normalized != newValue {
                            code = normalized
                        }
                    }
                    .onSubmit(submit)
                    .accessibilityLabel("Room code")
                    .accessibilityHint("\(RoomCode.length) letters and numbers")
                    .accessibilityIdentifier("rooms.code.field")
                Button(action: submit) {
                    Text("Join")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glowPrimary)
                .disabled(!RoomCode.isComplete(code))
                .accessibilityIdentifier("rooms.code.join")
            }
            .padding(24)
        }
        .navigationTitle("Room code")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func submit() {
        guard RoomCode.isComplete(code) else { return }
        focused = false
        submitted = code
    }
}

/// A room link from a QR code, a poster, a universal link or `glow://` in Debug: looks the room
/// up, runs the location check, then sends `.checkIn(roomID, ticket)`.
public struct RoomJoinView: View {
    public let link: RoomLink

    public init(link: RoomLink) {
        self.link = link
    }

    public var body: some View {
        if let entry = RoomEntry(link: link) {
            JoinFlowView(entry: entry, label: link.slug)
        } else {
            RoomCodeEntryView(note: "This link didn't include the room's code. Type the code shown in the room.")
        }
    }
}

#Preview("Rooms") {
    NavigationStack { RoomsHomeView() }
}

#Preview("Room code") {
    NavigationStack { RoomCodeEntryView() }
}
