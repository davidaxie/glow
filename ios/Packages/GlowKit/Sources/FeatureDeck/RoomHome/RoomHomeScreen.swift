import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: C1. The room home: the room's name, my check-in status and time left, Visible or Paused,
// See today's looks, and Leave.

struct RoomHomeScreen: View {
    @Bindable var model: RoomHomeModel

    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies
    @Environment(\.deckClock) private var clock

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .tint(.glowTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(failure):
                GlowEmptyState(
                    systemImage: failure == .offline ? "wifi.slash" : "exclamationmark.triangle",
                    title: LocalizedStringKey(failure == .offline ? DeckCopy.offline : DeckCopy.roomLoadFailed),
                ) {
                    Button(DeckCopy.tryAgain) { Task { await model.load() } }
                        .buttonStyle(.glowSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(snapshot):
                loaded(snapshot)
            }
        }
        .background(.glowBackground)
        .navigationTitle(model.snapshot?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .glowToast($model.toast)
        .confirmationDialog(DeckCopy.leaveTitle, isPresented: $model.isConfirmingLeave, titleVisibility: .visible) {
            Button(DeckCopy.leaveConfirm, role: .destructive) {
                Task { await leave() }
            }
            .accessibilityIdentifier("room.leave.confirm")
            Button(DeckCopy.stay, role: .cancel) {}
        } message: {
            Text(DeckCopy.leaveMessage)
        }
        .refreshable { await model.load() }
        .task {
            for await me in dependencies.session.profiles() {
                if let me {
                    model.profileChanged(paused: me.profile.paused)
                }
            }
        }
        .task(id: model.roomID) {
            await followRoom()
        }
        .accessibilityIdentifier("screen.FeatureDeck.roomHome")
    }

    private func loaded(_ snapshot: RoomSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    RoomStatusCard(snapshot: snapshot, now: clock(), checkInAgain: checkInAgain(snapshot))
                }
                RoomVisibilityCard(model: model) { visible in
                    if await model.setVisible(visible) {
                        _ = try? await dependencies.session.refreshProfile()
                    }
                }
                Text(DeckCopy.tapsLeft(snapshot.tapsLeftToday))
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .padding(.horizontal, GlowSpacing.xxs)
                    .accessibilityIdentifier("room.tapsLeft")
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.sm)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GlowSpacing.xs) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Button(DeckCopy.seeLooks) {
                        navigate(.deck(model.roomID))
                    }
                    .buttonStyle(.glowPrimary)
                    .disabled(!snapshot.isCheckedIn(at: clock()) || model.paused)
                    .accessibilityIdentifier("room.seeLooks")
                }
                Button(DeckCopy.leave) {
                    model.isConfirmingLeave = true
                }
                .buttonStyle(.glowQuiet)
                .glowLoading(model.isLeaving)
                .accessibilityIdentifier("room.leave")
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.xs)
            .background(.glowBackground)
        }
    }

    private func checkInAgain(_ snapshot: RoomSnapshot) -> Route {
        // A QR code or the room code, then the location check again: a link alone never gets
        // anyone back into a room (spec).
        .joinRoom(RoomLink(slug: snapshot.slug, token: nil))
    }

    private func leave() async {
        guard await model.leave() else { return }
        await dependencies.realtime.leaveRoom()
        navigate(.rooms)
    }

    /// Loads the room, joins its channel while I'm checked in, and refetches when my check-in is
    /// ending.
    private func followRoom() async {
        let realtime = dependencies.realtime
        let room = model.roomID
        await model.load()
        if model.snapshot?.isCheckedIn(at: .now) == true {
            try? await realtime.join(room: room)
        }
        for await event in realtime.events(for: room) where event.kind == .checkinExpiring {
            await model.load()
        }
    }
}

/// Checked in with time left, or why not, with Check in again.
struct RoomStatusCard: View {
    let snapshot: RoomSnapshot
    let now: Date
    let checkInAgain: Route

    @Environment(\.navigate) private var navigate

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.sm) {
            HStack(alignment: .top, spacing: GlowSpacing.sm) {
                Image(systemName: icon)
                    .font(.glow(.title))
                    .foregroundStyle(isActive ? AnyShapeStyle(.glowAccent) : AnyShapeStyle(.glowTextSecondary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                    Text(title)
                        .glowFont(.headline)
                        .foregroundStyle(.glowTextPrimary)
                    if let detail {
                        Text(detail)
                            .glowFont(.callout)
                            .foregroundStyle(.glowTextSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("room.status")
            if showsCheckInAgain {
                Button(DeckCopy.checkInAgain) { navigate(checkInAgain) }
                    .buttonStyle(.glowSecondary)
                    .accessibilityIdentifier("room.checkInAgain")
            }
        }
        .padding(GlowSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
    }

    private var isActive: Bool {
        snapshot.status == .live && snapshot.isCheckedIn(at: now) && snapshot.checkin?.visible == true
    }

    private var icon: String {
        if snapshot.status != .live {
            return "moon.zzz"
        }
        guard snapshot.isCheckedIn(at: now) else { return "hourglass" }
        return snapshot.checkin?.visible == false ? "eye.slash" : "checkmark.seal.fill"
    }

    private var title: String {
        switch snapshot.status {
        case .ended: return DeckCopy.roomEnded
        case .paused: return DeckCopy.roomPaused
        case .live: break
        }
        guard let checkin = snapshot.checkin, checkin.expiresAt > now else { return DeckCopy.checkinEnded }
        return checkin.visible ? DeckCopy.checkedIn : DeckCopy.cardRemoved
    }

    private var detail: String? {
        guard snapshot.status == .live, let checkin = snapshot.checkin, checkin.expiresAt > now else { return nil }
        return checkin.visible ? DeckCopy.timeLeft(checkin.expiresAt.timeIntervalSince(now)) : DeckCopy.cardRemovedDetail
    }

    private var showsCheckInAgain: Bool {
        guard snapshot.status == .live else { return false }
        guard let checkin = snapshot.checkin, checkin.expiresAt > now else { return true }
        return !checkin.visible
    }
}

/// Visible or Paused. Paused applies everywhere: nobody sees me, and I see nobody (P8).
struct RoomVisibilityCard: View {
    @Bindable var model: RoomHomeModel
    let setVisible: @MainActor (Bool) async -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { !model.paused },
            set: { visible in Task { await setVisible(visible) } },
        )) {
            VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                Text(DeckCopy.visible)
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Text(model.paused ? DeckCopy.pausedDetail : DeckCopy.visibleDetail)
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(.glowAccent)
        .disabled(model.isChangingPause)
        .padding(GlowSpacing.md)
        .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
        .accessibilityIdentifier("room.visible")
    }
}
