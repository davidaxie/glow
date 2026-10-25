import AppCore
import DesignSystem
import Observation
import SwiftUI

/// Loads what the reveal screen shows.
@MainActor
@Observable
final class BlindRevealScreenModel {
    enum Phase: Equatable {
        case loading
        /// Both tapped: the partner is shown.
        case revealed
        /// The chat exists but isn't revealed (B1: nothing about them is shown).
        case notRevealed
        /// 404: the chat is gone for me.
        case unavailable
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var detail: BlindChatDetail?
    private var lastRefresh = Date.distantPast

    var partner: BlindPartner? {
        detail?.partner
    }

    func load(_ chatID: BlindChatID, using service: any BlindService) async {
        lastRefresh = Date()
        do {
            let chat = try await service.chat(chatID)
            detail = chat
            // The partner only exists on a revealed chat (B1); never trust the status alone.
            phase = chat.status == .revealed && chat.partner != nil ? .revealed : .notRevealed
        } catch .notFound {
            phase = .unavailable
        } catch {
            if phase == .loading {
                phase = .failed(error.message)
            }
        }
    }

    /// Photo links last a minute. Reloads the chat for fresh ones, at most every 20 seconds.
    func refreshLinks(_ chatID: BlindChatID, using service: any BlindService, now: Date = Date()) async {
        guard now.timeIntervalSince(lastRefresh) > 20 else { return }
        await load(chatID, using: service)
    }
}

/// After both tapped Reveal: the veil lifts. Frost and blur dissolve from the center outward over
/// about 1.2 s, the name typesets in, their photos settle side by side, with the heartbeat haptic.
/// Opened by `.blindReveal(id)`.
public struct BlindRevealScreen: View {
    let chatID: BlindChatID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @Environment(\.navigate) private var navigate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = BlindRevealScreenModel()
    @State private var images: BlindImageStore?
    /// 0 is fully veiled, 1 is lifted.
    @State private var lift: Double = 0
    @State private var typeset = 0
    @State private var settled = false

    public init(chatID: BlindChatID) {
        self.chatID = chatID
    }

    private var service: any BlindService {
        dependencies.blindService(override: override)
    }

    public var body: some View {
        ZStack {
            BlindCanvas()
            switch model.phase {
            case .loading:
                BlindVeilOrb(seed: chatID.rawValue, size: 96).blindBreathing()
            case .revealed:
                if let partner = model.partner, let images {
                    revealed(partner, images: images)
                }
            case .notRevealed:
                message("Not revealed yet", "You'll see them here once you both tap Reveal.")
            case .unavailable:
                message("This chat isn't available", "It may have been closed.")
            case let .failed(text):
                message("Couldn't load", LocalizedStringKey(text), retry: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blind.reveal.screen")
        .task {
            if images == nil {
                images = BlindImageStore(service: service)
            }
            await model.load(chatID, using: service)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshLinks(chatID, using: service) }
            }
        }
        .onChange(of: model.phase) { _, phase in
            guard phase == .revealed else { return }
            Task { await play() }
        }
    }

    // MARK: Revealed

    private func revealed(_ partner: BlindPartner, images: BlindImageStore) -> some View {
        VStack(spacing: GlowSpacing.lg) {
            VStack(spacing: GlowSpacing.xs) {
                Text("You both said yes")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowAccent)
                    .opacity(settled ? 1 : 0)
                typesetName(partner.name)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(partner.name))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("blind.reveal.name")
                if let codename = model.detail?.codename {
                    Text("You knew them as \(codename)")
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                        .opacity(settled ? 1 : 0)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, GlowSpacing.xl)

            photos(partner, images: images)

            guessResult

            Spacer(minLength: 0)

            VStack(spacing: GlowSpacing.xs) {
                Button("Back to the chat") { navigate(.blindChat(chatID)) }
                    .buttonStyle(.glowPrimary)
                    .accessibilityIdentifier("blind.reveal.backToChat")
                Button("All chats") {
                    BlindTabState.shared.section = .chats
                    navigate(.blind)
                }
                .buttonStyle(.glowQuiet)
                .accessibilityIdentifier("blind.reveal.allChats")
            }
            .opacity(settled ? 1 : 0)
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.bottom, GlowSpacing.lg)
    }

    /// The name sets in letter by letter, 40 ms apart.
    private func typesetName(_ name: String) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(name.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(BlindType.revealName)
                    .foregroundStyle(.glowTextPrimary)
                    .opacity(index < typeset ? 1 : 0)
                    .offset(y: index < typeset || reduceMotion ? 0 : 6)
                    .blur(radius: index < typeset ? 0 : 4)
            }
        }
        .tracking(-0.5)
    }

    private func photos(_ partner: BlindPartner, images: BlindImageStore) -> some View {
        HStack(spacing: GlowSpacing.sm) {
            if partner.photos.isEmpty {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.glowSurface)
            }
            ForEach(Array(partner.photos.prefix(2).enumerated()), id: \.offset) { index, photo in
                BlindPhotoView(photo: photo, store: images) {
                    Task { await model.refreshLinks(chatID, using: service) }
                }
                .offset(x: settled || reduceMotion ? 0 : (index == 0 ? 18 : -18))
                .rotationEffect(.degrees(settled || reduceMotion ? 0 : (index == 0 ? -3 : 3)))
                .accessibilityIdentifier("blind.reveal.photo.\(index)")
            }
        }
        .frame(maxHeight: .infinity)
        .modifier(BlindVeilLift(progress: lift))
    }

    @ViewBuilder private var guessResult: some View {
        if let correct = model.detail?.guessCorrect {
            Label(
                correct ? "You guessed right." : "Not who you guessed.",
                systemImage: correct ? "checkmark.circle" : "arrow.triangle.2.circlepath",
            )
            .glowFont(.footnote)
            .foregroundStyle(correct ? .glowAccent : .glowTextSecondary)
            .opacity(settled ? 1 : 0)
            .accessibilityIdentifier(correct ? "blind.reveal.guess.right" : "blind.reveal.guess.wrong")
        }
    }

    private func play() async {
        BlindHaptics.playHeartbeat()
        if reduceMotion {
            withAnimation(BlindMotion.fade) {
                lift = 1
                typeset = .max
                settled = true
            }
            return
        }
        withAnimation(.easeOut(duration: BlindMotion.veilLift)) { lift = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        let letters = model.partner?.name.count ?? 0
        for index in 0 ..< letters {
            withAnimation(BlindMotion.smooth) { typeset = index + 1 }
            try? await Task.sleep(for: BlindMotion.stagger)
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(BlindMotion.gentle) { settled = true }
    }

    // MARK: Other states

    private func message(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, retry: Bool = false) -> some View {
        VStack(spacing: GlowSpacing.md) {
            Text(title).font(BlindType.statement).foregroundStyle(.glowTextPrimary)
            Text(detail).glowFont(.body).foregroundStyle(.glowTextSecondary).multilineTextAlignment(.center)
            if retry {
                Button("Try again") { Task { await model.load(chatID, using: service) } }.buttonStyle(.glowSecondary)
            }
            Button("Back to the chat") { navigate(.blindChat(chatID)) }.buttonStyle(.glowQuiet)
        }
        .padding(GlowSpacing.screenMargin)
    }
}

/// The veil: frost and blur that dissolve from the center outward as `progress` goes 0 to 1.
private struct BlindVeilLift: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: 26 * (1 - progress))
            .overlay {
                GeometryReader { proxy in
                    let radius = hypot(proxy.size.width, proxy.size.height) / 2
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Rectangle().fill(.glowSurface.opacity(0.35)))
                        .mask {
                            // Clear in the middle, frosted outside, the clear hole growing outward.
                            RadialGradient(
                                stops: [
                                    .init(color: .glowClear, location: 0),
                                    .init(color: .glowClear, location: max(0, progress * 1.1 - 0.1)),
                                    .init(color: .glowBackground, location: min(1, progress * 1.1 + 0.05)),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: radius,
                            )
                        }
                        .opacity(progress >= 1 ? 0 : 1)
                }
                .allowsHitTesting(false)
            }
    }
}
