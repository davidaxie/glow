import AppCore
import DesignSystem
import SwiftUI

// Owner: C1, redrawn by U2 (design wave). The enlarged card: the whole photo (so the watermark
// shows in full), its tags, and That's them under the thumb. Swipe sideways for the next look.
// Drawn inside the deck screen, not presented, so the deck's privacy cover (P12) covers it too.
//
// A one-sided tap is acknowledged here and only here: a soft ripple of light through the card and
// "Noted. Only you know.", then it settles (DIRECTION.md). Nothing ever reaches the other phone (P5).

struct CardDetailView: View {
    @Bindable var model: DeckModel
    /// The tap was mutual: hand off to FeatureMatch's takeover.
    let onMutual: @MainActor (MatchID) -> Void

    @Environment(\.navigate) private var navigate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card whose tap just went through, and a counter that sets off its ripple.
    @State private var rippleCard: CardID?
    @State private var ripple = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let card = model.enlargedCard {
                    Menu {
                        Button(role: .destructive) {
                            model.hideForSafety(card.id)
                            navigate(.block(.card(card.id)))
                        } label: {
                            Label(DeckCopy.block, systemImage: "hand.raised")
                        }
                        Button {
                            model.hideForSafety(card.id)
                            navigate(.report(.card(card.id)))
                        } label: {
                            Label(DeckCopy.report, systemImage: "exclamationmark.bubble")
                        }
                    } label: {
                        DeckRoundGlyph(systemImage: "ellipsis")
                    }
                    .accessibilityLabel(Text(DeckCopy.more))
                    .accessibilityIdentifier("deck.detail.more")
                }
                Spacer()
                Button {
                    model.close()
                } label: {
                    DeckRoundGlyph(systemImage: "xmark")
                }
                .buttonStyle(DeckPressStyle())
                .accessibilityLabel(Text(DeckCopy.close))
                .accessibilityIdentifier("deck.detail.close")
            }
            .padding(.horizontal, GlowSpacing.screenMargin)

            TabView(selection: $model.enlarged) {
                ForEach(model.cards) { card in
                    VStack(spacing: GlowSpacing.md) {
                        DeckCardImage(url: card.imageURL, contentMode: .fit) {
                            model.imageUnavailable(card.id)
                        }
                        .overlay {
                            if let code = model.viewerCode {
                                GlowWatermark(code)
                            }
                        }
                        .overlay { DeckRipple(trigger: card.id == rippleCard ? ripple : 0) }
                        .clipShape(RoundedRectangle(cornerRadius: DeckLight.cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DeckLight.cardRadius, style: .continuous)
                                .strokeBorder(
                                    card
                                        .tappedByMe ? AnyShapeStyle(Color.glowAccent.opacity(0.8)) :
                                        AnyShapeStyle(Color.glowTextPrimary.opacity(0.12)),
                                    lineWidth: card.tappedByMe ? 1.5 : 1,
                                )
                        }
                        .shadow(
                            color: card.tappedByMe ? Color.glowAccent.opacity(0.4) : Color.glowBackground.opacity(0.7),
                            radius: 24,
                            y: 12,
                        )
                        .glowHiddenWhenCaptured()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(DeckCopy.describe(card.tags)))
                        .accessibilityAddTraits(.isImage)
                        DeckTagRow(tags: card.tags)
                    }
                    .padding(.horizontal, GlowSpacing.screenMargin)
                    .padding(.vertical, GlowSpacing.sm)
                    .tag(Optional(card.id))
                    .onAppear {
                        if card.id == model.cards.last?.id {
                            Task { await model.loadMore() }
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            actions
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.bottom, GlowSpacing.sm)
        }
        .background { DeckCanvas(warmth: model.enlargedCard?.tappedByMe == true ? 0.9 : 0.5) }
        .overlay {
            ZStack(alignment: .bottom) {
                if model.confirmingCard != nil {
                    Rectangle()
                        .fill(Color.glowBackground.opacity(0.72))
                        .ignoresSafeArea()
                        .onTapGesture { model.cancelTap() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if let card = model.confirmingCard {
                    TapConfirmPanel(model: model, card: card, onMutual: onMutual)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(DeckLight.motion(DeckLight.smooth, reduceMotion: reduceMotion), value: model.confirming)
        .animation(DeckLight.motion(DeckLight.gentle, reduceMotion: reduceMotion), value: model.enlargedCard?.tappedByMe)
        .onChange(of: OpenCard(id: model.enlarged, tapped: model.enlargedCard?.tappedByMe == true)) { was, now in
            // Only the card on screen turning tapped; swiping onto a card tapped earlier is quiet.
            guard let card = now.id, was.id == card, !was.tapped, now.tapped else { return }
            acknowledgeTap(card)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: ripple)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.detail")
    }

    /// The quiet acknowledgement: the note moves from a banner into the card, light ripples
    /// through it once, a soft haptic, and VoiceOver hears the same words.
    private func acknowledgeTap(_ card: CardID) {
        if model.toast?.text == DeckCopy.tapSent {
            model.toast = nil
        }
        rippleCard = card
        ripple += 1
        AccessibilityNotification.Announcement(DeckCopy.tapSent).post()
    }

    @ViewBuilder private var actions: some View {
        if let card = model.enlargedCard {
            VStack(spacing: GlowSpacing.xs) {
                if card.tappedByMe {
                    DeckTapNoted(justNow: card.id == rippleCard)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                } else if model.tapsLeftToday == 0 {
                    Button(DeckCopy.thatsThem) {}
                        .buttonStyle(.glowPrimary)
                        .disabled(true)
                        .accessibilityHint(Text(DeckCopy.noTapsLeft))
                    Text(DeckCopy.noTapsLeft)
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                } else {
                    Button(DeckCopy.thatsThem) {
                        model.requestTap(card.id)
                    }
                    .buttonStyle(.glowPrimary)
                    .shadow(color: Color.glowAccent.opacity(0.35), radius: 18, y: 6)
                    .accessibilityIdentifier("deck.detail.thatsThem")
                    .transition(.opacity)
                }
            }
            .frame(minHeight: GlowSize.buttonHeight + GlowSpacing.md)
        }
    }
}

/// The open card and whether I've tapped it, to notice the moment a tap goes through.
private struct OpenCard: Equatable {
    let id: CardID?
    let tapped: Bool
}

/// "Noted. Only you know.": what a one-sided tap leaves behind, on my screen only.
struct DeckTapNoted: View {
    /// The tap went through just now (rather than earlier today).
    let justNow: Bool

    var body: some View {
        VStack(spacing: GlowSpacing.xxs) {
            HStack(spacing: GlowSpacing.xs) {
                Image(systemName: "sparkle")
                    .glowFont(.headline)
                    .foregroundStyle(.glowAccent)
                    .symbolEffect(.bounce, value: justNow)
                Text(justNow ? DeckCopy.tapSent : DeckCopy.youTappedThem)
                    .font(DeckLight.titleSerif)
                    .tracking(-0.3)
                    .foregroundStyle(.glowTextPrimary)
            }
            Text(DeckCopy.tapSentDetail)
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, GlowSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deck.detail.noted")
    }
}

/// A round glass button face for the close and more buttons.
struct DeckRoundGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.glow(.headline))
            .foregroundStyle(.glowTextPrimary)
            .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.glowTextPrimary.opacity(0.12), lineWidth: 1))
    }
}

/// "That's them?": they won't know unless they tap you too, with taps left today.
struct TapConfirmPanel: View {
    @Bindable var model: DeckModel
    let card: DeckCard
    let onMutual: @MainActor (MatchID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.md) {
            Capsule()
                .fill(Color.glowTextPrimary.opacity(0.2))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text(DeckCopy.confirmTitle)
                    .font(DeckLight.displaySerif)
                    .tracking(-0.5)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(DeckCopy.confirmMessage)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            DeckTagRow(tags: card.tags)
            if let left = model.tapsLeftToday {
                Label(DeckCopy.tapsLeft(left), systemImage: "lock")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("deck.confirm.tapsLeft")
            }
            VStack(spacing: GlowSpacing.xs) {
                Button(DeckCopy.confirmTap) {
                    Task {
                        if let match = await model.confirmTap() {
                            onMutual(match)
                        }
                    }
                }
                .buttonStyle(.glowPrimary)
                .glowLoading(model.isTapping)
                .shadow(color: Color.glowAccent.opacity(0.35), radius: 18, y: 6)
                .accessibilityIdentifier("deck.confirm.tap")
                Button(DeckCopy.notYet) {
                    model.cancelTap()
                }
                .buttonStyle(.glowQuiet)
                .disabled(model.isTapping)
                .accessibilityIdentifier("deck.confirm.cancel")
            }
            .padding(.top, GlowSpacing.xs)
        }
        .padding(.horizontal, GlowSpacing.screenMargin + GlowSpacing.xxs)
        .padding(.top, GlowSpacing.sm)
        .padding(.bottom, GlowSpacing.md)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: DeckLight.sheetRadius + 8,
                topTrailingRadius: DeckLight.sheetRadius + 8,
                style: .continuous,
            )
            .fill(.ultraThinMaterial)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: DeckLight.sheetRadius + 8,
                    topTrailingRadius: DeckLight.sheetRadius + 8,
                    style: .continuous,
                )
                .fill(Color.glowSurface.opacity(0.85)),
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: DeckLight.sheetRadius + 8,
                    topTrailingRadius: DeckLight.sheetRadius + 8,
                    style: .continuous,
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.glowTextPrimary.opacity(0.18), Color.glowTextPrimary.opacity(0)],
                        startPoint: .top,
                        endPoint: .center,
                    ),
                    lineWidth: 1,
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.confirm")
    }
}
