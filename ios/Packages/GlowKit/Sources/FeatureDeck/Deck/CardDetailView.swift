import AppCore
import DesignSystem
import SwiftUI

// Owner: C1. The enlarged card: the whole photo (so the watermark shows in full), its tags, and
// That's them under the thumb. Swipe sideways for the next look. Drawn inside the deck screen, not
// presented, so the deck's privacy cover (P12) covers it too.

struct CardDetailView: View {
    @Bindable var model: DeckModel
    /// The tap was mutual: hand off to FeatureMatch's takeover.
    let onMutual: @MainActor (MatchID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.glow(.headline))
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                }
                .buttonStyle(.glow(.secondary, size: .compact))
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
                        .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
                        .accessibilityLabel(Text(DeckCopy.describe(card.tags)))
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
        .background(.glowBackground)
        .overlay {
            if let card = model.confirmingCard {
                TapConfirmPanel(model: model, card: card, onMutual: onMutual)
                    .transition(.opacity)
            }
        }
        .glowAnimation(value: model.confirming)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("deck.detail")
    }

    @ViewBuilder private var actions: some View {
        if let card = model.enlargedCard {
            VStack(spacing: GlowSpacing.xs) {
                if card.tappedByMe {
                    Button(DeckCopy.youTappedThem) {}
                        .buttonStyle(.glowSecondary)
                        .disabled(true)
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
                    .accessibilityIdentifier("deck.detail.thatsThem")
                }
            }
        }
    }
}

/// "That's them?": they won't know unless they tap you too, with taps left today.
struct TapConfirmPanel: View {
    @Bindable var model: DeckModel
    let card: DeckCard
    let onMutual: @MainActor (MatchID) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.glowBackground.opacity(0.7))
                .ignoresSafeArea()
                .onTapGesture { model.cancelTap() }
                .accessibilityHidden(true)
            GlowSheetContent(
                title: LocalizedStringKey(DeckCopy.confirmTitle),
                message: LocalizedStringKey(DeckCopy.confirmMessage),
                systemImage: "hand.tap",
            ) {
                DeckTagRow(tags: card.tags)
                if let left = model.tapsLeftToday {
                    Text(DeckCopy.tapsLeft(left))
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                        .accessibilityIdentifier("deck.confirm.tapsLeft")
                }
            } actions: {
                Button(DeckCopy.confirmTap) {
                    Task {
                        if let match = await model.confirmTap() {
                            onMutual(match)
                        }
                    }
                }
                .buttonStyle(.glowPrimary)
                .glowLoading(model.isTapping)
                .accessibilityIdentifier("deck.confirm.tap")
                Button(DeckCopy.notYet) {
                    model.cancelTap()
                }
                .buttonStyle(.glowQuiet)
                .disabled(model.isTapping)
                .accessibilityIdentifier("deck.confirm.cancel")
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.lg)
            .padding(.bottom, GlowSpacing.md)
            .background(.glowSurface, in: UnevenRoundedRectangle(topLeadingRadius: GlowRadius.card, topTrailingRadius: GlowRadius.card))
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("deck.confirm")
        }
    }
}
