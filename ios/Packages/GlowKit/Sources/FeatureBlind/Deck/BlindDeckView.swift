import AppCore
import DesignSystem
import SwiftUI

/// A card that has been swiped away and is still flying off.
private struct LeavingCard: Identifiable {
    let id = UUID()
    let entry: BlindDeckEntry
    let kind: BlindSwipeKind
    let start: CGSize
}

/// The Blind deck: full-bleed photos, drag left to pass, right to like, up to love, with buttons as
/// a fallback. Photos only (no names, ages or anything about rooms). The only numbers on screen are
/// mine: right swipes left today (B4) and progress toward the five that open a drop (B3). Nothing
/// here can say who liked back (B2).
struct BlindDeckView: View {
    let model: BlindDeckModel
    let images: BlindImageStore

    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var hinted: BlindSwipeKind?
    @State private var leaving: [LeavingCard] = []
    @State private var shake: CGFloat = 0
    @State private var arrived = false
    @State private var swipes = 0

    var body: some View {
        VStack(spacing: GlowSpacing.sm) {
            header
            ZStack { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glowHiddenWhenCaptured()
            if model.capReached, model.phase == .ready {
                capBanner.transition(.opacity)
            }
            if let error = model.errorText {
                Text(error)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowDanger)
                    .transition(.opacity)
            }
            BlindSwipeButtons(canSwipeRight: model.canSwipeRight, isEnabled: model.top != nil) { kind in
                perform(kind, start: .zero)
            }
            .padding(.bottom, GlowSpacing.xs)
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .animation(BlindMotion.fade, value: model.errorText)
        .animation(BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion), value: model.capReached)
        .glowHaptic(.lightTap, trigger: swipes)
        .glowHaptic(.warning, trigger: model.capNudge)
        .onChange(of: model.capNudge) { _, _ in
            withAnimation(BlindMotion.snappy) { shake += 1 }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshOnForeground() }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: GlowSpacing.xs) {
            HStack(spacing: GlowSpacing.sm) {
                Text(model.capReached ? String(localized: "No right swipes left today") : BlindDeckRules
                    .remainingText(model.rightRemaining))
                    .glowFont(.footnote)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(model.capReached ? .glowTextPrimary : .glowTextSecondary)
                    .accessibilityIdentifier("blind.deck.remaining")
                Spacer(minLength: GlowSpacing.xs)
                if let progress = model.dropProgressText {
                    Text(progress)
                        .glowFont(.caption)
                        .foregroundStyle(.glowTextSecondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("blind.deck.dropProgress")
                } else {
                    Button {
                        navigate(.blindDrop)
                    } label: {
                        Label("Open your drop", systemImage: "sparkles")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.glow(.primary, size: .compact))
                    .accessibilityIdentifier("blind.deck.openDrop")
                }
            }
            BlindDropMarks(filled: BlindDeckRules.filledDots(rightCount: model.rightCount))
        }
        .animation(BlindMotion.motion(BlindMotion.snappy, reduceMotion: reduceMotion), value: model.rightCount)
    }

    // MARK: Cards

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.glowSurface)
                .overlay { BlindVeilOrb(seed: "deck", size: 96).blindBreathing() }
        case let .failed(message):
            GlowEmptyState(systemImage: "wifi.slash", title: "Couldn't load the deck", message: LocalizedStringKey(message)) {
                Button("Try again") { Task { await model.retry() } }.buttonStyle(.glowSecondary)
            }
        case .ready where model.entries.isEmpty && leaving.isEmpty:
            emptyState
        case .ready:
            GeometryReader { proxy in
                ZStack {
                    stack
                    ForEach(leaving) { card in
                        BlindLeavingCardView(card: card, images: images, size: proxy.size)
                            .allowsHitTesting(false)
                    }
                }
            }
            .onAppear { arrived = true }
        }
    }

    private var stack: some View {
        let visible = Array(model.entries.prefix(3).enumerated())
        let progress = min(max(hypot(drag.width, drag.height) / BlindSwipeGesture.commitX, 0), 1)
        return ZStack {
            ForEach(visible.reversed(), id: \.element.id) { index, entry in
                let isTop = index == 0
                let depth = CGFloat(index)
                BlindPhotoView(photo: entry.card.photo, store: images)
                    .overlay {
                        if isTop {
                            stamps
                        }
                    }
                    .scaleEffect(isTop ? 1 : 1 - 0.05 * depth + 0.05 * progress * (index == 1 ? 1 : 0))
                    .offset(
                        x: isTop ? drag.width : 0,
                        y: isTop ? drag.height : (14 * depth) * (index == 1 ? 1 - progress : 1),
                    )
                    .rotationEffect(.degrees(isTop ? Double(drag.width) / 18 : 0), anchor: UnitPoint(x: 0.5, y: 1.15))
                    // The deck arrives with a staggered rise (40 ms apart).
                    .offset(y: arrived || reduceMotion ? 0 : 60)
                    .opacity(arrived ? 1 : 0)
                    .animation(
                        BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion)
                            .delay(Double(2 - index) * BlindMotion.staggerSeconds),
                        value: arrived,
                    )
                    .zIndex(Double(3 - index))
                    .gesture(dragGesture, including: isTop ? .all : .none)
                    .accessibilityElement(children: isTop ? .contain : .ignore)
                    .accessibilityLabel(Text("Photo"))
                    .accessibilityHint(Text("Swipe right to like, left to pass, up to love."))
                    .accessibilityAction(named: Text("Pass")) { perform(.pass, start: .zero) }
                    .accessibilityAction(named: Text("Like")) { perform(.like, start: .zero) }
                    .accessibilityAction(named: Text("Love")) { perform(.love, start: .zero) }
                    .accessibilityIdentifier(isTop ? "blind.deck.topCard" : "blind.deck.nextCard")
            }
        }
        .animation(BlindMotion.motion(BlindMotion.snappy, reduceMotion: reduceMotion), value: model.entries.prefix(3).map(\.id))
    }

    private var stamps: some View {
        let strength = BlindSwipeGesture.stamps(translation: drag)
        return ZStack {
            BlindSwipeStamp(kind: .like, strength: strength.like)
                .rotationEffect(.degrees(-10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(GlowSpacing.lg)
            BlindSwipeStamp(kind: .pass, strength: strength.pass)
                .rotationEffect(.degrees(10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(GlowSpacing.lg)
            BlindSwipeStamp(kind: .love, strength: strength.love)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(GlowSpacing.xxl)
        }
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                drag = value.translation
                hinted = BlindSwipeGesture.intent(translation: value.translation, predicted: value.translation)
            }
            .onEnded { value in
                hinted = nil
                if let kind = BlindSwipeGesture.intent(translation: value.translation, predicted: value.predictedEndTranslation) {
                    perform(kind, start: value.translation)
                } else {
                    withAnimation(BlindMotion.snappy) { drag = .zero }
                }
            }
    }

    /// Sends the swipe and flies the card off. A right swipe with none left springs back (B4).
    private func perform(_ kind: BlindSwipeKind, start: CGSize) {
        guard let entry = model.commit(kind) else {
            withAnimation(BlindMotion.snappy) { drag = .zero }
            return
        }
        swipes += 1
        let card = LeavingCard(entry: entry, kind: kind, start: start)
        leaving.append(card)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { drag = .zero }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            leaving.removeAll { $0.id == card.id }
        }
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: GlowSpacing.lg) {
            Spacer()
            BlindVeilOrb(seed: "everyone", size: 88).blindBreathing()
            Text("You've seen everyone for now.")
                .font(BlindType.statement)
                .foregroundStyle(.glowTextPrimary)
                .multilineTextAlignment(.center)
            Text(
                model.canOpenDrop
                    ? String(localized: "New people appear as more join. Your drop is ready when you are.")
                    :
                    String(localized: """
                    New people appear as more join. \
                    Like \(BlindDeckRules.dropMinimum - model.rightCount) more to open your drop.
                    """),
            )
            .glowFont(.body)
            .foregroundStyle(.glowTextSecondary)
            .multilineTextAlignment(.center)
            Button("Check again") { Task { await model.checkAgain() } }
                .buttonStyle(.glow(.secondary, size: .compact))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blind.deck.empty")
    }

    private var capBanner: some View {
        HStack(spacing: GlowSpacing.sm) {
            Image(systemName: "moon.stars")
                .glowFont(.headline)
                .foregroundStyle(.glowAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                Text("You're out of right swipes for today")
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                Text("\(BlindDeckRules.resetText(now: Date())). You can still pass.")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(GlowSpacing.md)
        .blindGlass(cornerRadius: 20)
        .modifier(BlindShake(travel: 8, shakes: shake))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blind.deck.capBanner")
    }
}

/// The card flying off: starts where the finger let go and leaves in the swipe direction.
private struct BlindLeavingCardView: View {
    let card: LeavingCard
    let images: BlindImageStore
    let size: CGSize
    @State private var offset: CGSize
    @State private var opacity = 1.0

    init(card: LeavingCard, images: BlindImageStore, size: CGSize) {
        self.card = card
        self.images = images
        self.size = size
        _offset = State(initialValue: card.start)
    }

    var body: some View {
        BlindPhotoView(photo: card.entry.card.photo, store: images)
            .overlay {
                BlindSwipeStamp(kind: card.kind, strength: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(card.kind == .love ? GlowSpacing.xxl : GlowSpacing.lg)
            }
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width) / 18), anchor: UnitPoint(x: 0.5, y: 1.15))
            .opacity(opacity)
            .onAppear {
                withAnimation(BlindMotion.snappy) { offset = target }
                withAnimation(BlindMotion.fade) { opacity = 0 }
            }
    }

    private var alignment: Alignment {
        switch card.kind {
        case .pass: .topTrailing
        case .like: .topLeading
        case .love: .bottom
        }
    }

    private var target: CGSize {
        switch card.kind {
        case .pass: CGSize(width: -size.width * 1.5, height: card.start.height + 40)
        case .like: CGSize(width: size.width * 1.5, height: card.start.height + 40)
        case .love: CGSize(width: card.start.width, height: -size.height * 1.3)
        }
    }
}
