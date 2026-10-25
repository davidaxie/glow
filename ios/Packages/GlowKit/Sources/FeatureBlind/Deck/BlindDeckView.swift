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
                Text(model.capReached ? String(localized: "No right swipes left today") : BlindDeckRules.remainingText(model.rightRemaining))
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
                        BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion).delay(Double(2 - index) * BlindMotion.staggerSeconds),
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
                    : String(localized: "New people appear as more join. Like \(BlindDeckRules.dropMinimum - model.rightCount) more to open your drop."),
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

/// Pass, Like or Love, fading in as the card is dragged.
private struct BlindSwipeStamp: View {
    let kind: BlindSwipeKind
    let strength: Double

    var body: some View {
        Label(title, systemImage: symbol)
            .glowFont(.headline)
            .foregroundStyle(kind == .pass ? .glowTextPrimary : .glowAccent)
            .padding(.horizontal, GlowSpacing.md)
            .padding(.vertical, GlowSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .pass ? .glowTextPrimary : .glowAccent, lineWidth: 2))
            .opacity(strength)
            .scaleEffect(0.9 + 0.1 * strength)
            .accessibilityHidden(true)
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .pass: "Pass"
        case .like: "Like"
        case .love: "Love"
        }
    }

    private var symbol: String {
        switch kind {
        case .pass: "xmark"
        case .like: "heart"
        case .love: "heart.fill"
        }
    }
}

/// Pass, Love and Like. Right-swipe buttons dim when none are left but stay tappable, so pressing
/// one explains why.
private struct BlindSwipeButtons: View {
    let canSwipeRight: Bool
    let isEnabled: Bool
    let action: (BlindSwipeKind) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: GlowSpacing.xl) {
            round(.pass, symbol: "xmark", title: "Pass", size: 60, filled: false)
            round(.love, symbol: "heart.fill", title: "Love", size: 72, filled: true)
                .opacity(canSwipeRight ? 1 : 0.4)
            round(.like, symbol: "heart", title: "Like", size: 60, filled: false)
                .opacity(canSwipeRight ? 1 : 0.4)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(isEnabled)
    }

    private func round(_ kind: BlindSwipeKind, symbol: String, title: LocalizedStringKey, size: CGFloat, filled: Bool) -> some View {
        Button {
            action(kind)
        } label: {
            VStack(spacing: GlowSpacing.xxs) {
                Image(systemName: symbol)
                    .glowFont(filled ? .title : .headline)
                    .foregroundStyle(filled ? .glowOnAccent : (kind == .pass ? .glowTextPrimary : .glowAccent))
                    .frame(width: size, height: size)
                    .background(filled ? .glowAccent : .glowSurfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(filled ? .glowClear : .glowLine, lineWidth: 1))
                Text(title).glowFont(.caption).foregroundStyle(.glowTextSecondary)
            }
        }
        .buttonStyle(BlindPressStyle())
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("blind.deck.\(kind.rawValue)")
    }
}

struct BlindPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(BlindMotion.snappy, value: configuration.isPressed)
    }
}

/// Five marks toward opening the drop.
struct BlindDropMarks: View {
    let filled: Int

    var body: some View {
        HStack(spacing: GlowSpacing.xs) {
            ForEach(0 ..< BlindDeckRules.dropMinimum, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? .glowAccent : .glowSurfaceRaised)
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(filled) of \(BlindDeckRules.dropMinimum) right swipes toward your drop"))
    }
}

/// A horizontal shake driven by an incrementing counter.
struct BlindShake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
    }
}
