import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: C1. The deck: a two-column grid of today's looks, pull to refresh, views left today shown
// quietly, What did you notice under the thumb, and the enlarged card on top.

struct DeckScreen: View {
    @Bindable var model: DeckModel
    /// Where "Check in again" goes.
    let checkInAgain: Route

    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cards rise in once the looks arrive (DIRECTION.md "Joining a room").
    @State private var risen = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DeckCanvas(warmth: model.phase == .loaded ? 0.55 : 0.35) }
            .overlay {
                if model.enlargedCard != nil {
                    CardDetailView(model: model) { match in
                        navigate(.mutual(match))
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(DeckLight.motion(DeckLight.smooth, reduceMotion: reduceMotion), value: model.enlarged)
            .onChange(of: model.phase, initial: true) { _, phase in
                risen = phase == .loaded
            }
            .deckPrivacy(model)
            .glowToast(toast)
            .navigationTitle(DeckCopy.deckTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(model.enlarged == nil ? .automatic : .hidden, for: .navigationBar, .tabBar)
            .sheet(isPresented: $model.isNoticeSheetOpen) {
                NoticeSheet(showMe: model.showMe, initial: model.filters) { noticed in
                    Task { await model.apply(noticed) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(GlowRadius.card)
                .presentationBackground(.glowSurface)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.FeatureDeck.deck")
            .task(id: model.roomID) {
                await listenForDeckChanges()
            }
            .task(id: scenePhase) {
                await refreshWhileActive()
            }
            .task {
                // Events sent while the connection was down are gone: refetch on every reconnect.
                for await state in dependencies.realtime.connectionStates().dropFirst() where state == .connected {
                    model.deckChanged()
                }
            }
    }

    /// The one-sided tap's "Noted. Only you know." is drawn quietly inside the card, never as a
    /// banner (DIRECTION.md "One-sided tap"); every other note is a toast.
    private var toast: Binding<GlowToastMessage?> {
        Binding(
            get: { model.toast?.text == DeckCopy.tapSent ? nil : model.toast },
            set: { model.toast = $0 },
        )
    }

    /// `deck.changed`: someone here paused, left or blocked. Their card goes within seconds (P8).
    private func listenForDeckChanges() async {
        let realtime = dependencies.realtime
        let room = model.roomID
        try? await realtime.join(room: room)
        for await event in realtime.events(for: room) where event.kind == .deckChanged {
            model.deckChanged()
        }
    }

    /// A safety net under realtime: a quiet refetch when the app comes back, and every 30 seconds
    /// while the deck is on screen, in case an event was missed (C1-D5).
    private func refreshWhileActive() async {
        guard scenePhase == .active else { return }
        model.deckChanged()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            model.deckChanged()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .choosing:
            DeckQuietState(title: DeckCopy.noticeTitle, message: DeckCopy.noticeSubtitle) {
                Button(DeckCopy.changeNoticed) { model.isNoticeSheetOpen = true }
                    .buttonStyle(.glowPrimary)
                    .padding(.top, GlowSpacing.xs)
                Button(DeckCopy.noticeSkip) { Task { await model.apply(.none) } }
                    .buttonStyle(.glowQuiet)
                    .accessibilityIdentifier("deck.skip")
            }
        case .loading:
            // A breath, not a spinner: the room is gathering its looks.
            ZStack {
                DeckBreathingLight(size: 220, intensity: 0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(DeckCopy.loadingLooks))
        case .loaded:
            grid
        case let .empty(reason):
            ScrollView {
                DeckEmptyView(reason: reason, model: model, checkInAgain: checkInAgain)
                    .padding(.top, GlowSpacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await model.refresh() }
        case let .failed(failure):
            DeckQuietState(title: failure == .offline ? DeckCopy.offline : DeckCopy.deckFailed, intensity: 0.45) {
                Button(DeckCopy.tryAgain) { Task { await model.apply(model.filters) } }
                    .buttonStyle(.glowSecondary)
            }
        }
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: GlowSpacing.md, alignment: .top), count: count)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                LazyVGrid(columns: columns, spacing: GlowSpacing.lg) {
                    ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                        Button {
                            model.open(card.id)
                        } label: {
                            DeckTile(card: card, viewerCode: model.viewerCode) { model.imageUnavailable(card.id) }
                        }
                        .buttonStyle(DeckPressStyle())
                        .deckRise(index: index, isVisible: risen)
                        .accessibilityIdentifier("deck.card.\(card.id.rawValue)")
                        .onAppear {
                            if card.id == model.cards.last?.id {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                }
                footer
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.sm)
            .padding(.bottom, GlowSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .safeAreaInset(edge: .bottom) { noticeBar }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.grid")
    }

    private var footer: some View {
        VStack(spacing: GlowSpacing.sm) {
            if model.isLoadingMore {
                ProgressView().tint(.glowTextSecondary)
            } else if model.loadMoreFailed {
                Button(DeckCopy.tryAgain) { Task { await model.loadMore() } }
                    .buttonStyle(.glow(.secondary, size: .compact))
                    .accessibilityHint(Text(DeckCopy.loadMoreFailed))
            }
            if let views = model.viewsLeftToday, !model.hasMore {
                Text(DeckCopy.viewsLeft(views))
                    .glowFont(.footnote)
                    .foregroundStyle(.glowTextSecondary)
                    .accessibilityIdentifier("deck.viewsLeft")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, GlowSpacing.sm)
    }

    /// What did you notice, at the bottom where a thumb reaches it.
    private var noticeBar: some View {
        Button {
            model.isNoticeSheetOpen = true
        } label: {
            HStack(spacing: GlowSpacing.xs) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .accessibilityHidden(true)
                }
                Text(model.filters.isEmpty ? DeckCopy.changeNoticed : DeckSummary.text(model.filters))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if !model.filters.isEmpty {
                    Text(DeckCopy.editNoticed)
                        .foregroundStyle(.glowAccent)
                }
            }
            .glowFont(.button)
            .foregroundStyle(.glowTextPrimary)
            .frame(maxWidth: .infinity, minHeight: GlowSize.buttonHeight)
            .padding(.horizontal, GlowSpacing.md)
            .deckGlass(cornerRadius: GlowSize.buttonHeight / 2)
            .contentShape(Capsule())
        }
        .buttonStyle(DeckPressStyle())
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.top, GlowSpacing.xs)
        .padding(.bottom, GlowSpacing.xs)
        .background {
            // The room fades out under the bar, so cards slip beneath it instead of being cut off.
            LinearGradient(
                colors: [Color.glowBackground.opacity(0), Color.glowBackground.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .accessibilityIdentifier("deck.notice.open")
    }
}

/// A press that answers the touch: the card dips a little on the snappy spring.
struct DeckPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(DeckLight.motion(DeckLight.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// A short summary of what I noticed, for the bar: "Green · Short · Glasses".
enum DeckSummary {
    static func text(_ filters: NoticedFilters) -> String {
        var parts: [String] = []
        parts += Gender.allCases.filter(filters.genders.contains).map(DeckCopy.name)
        parts += TopColor.allCases.filter(filters.topColors.contains).map(DeckCopy.name)
        parts += HairLength.allCases.filter(filters.hairLengths.contains).map(DeckCopy.name)
        parts += HairColor.allCases.filter(filters.hairColors.contains).map(DeckCopy.name)
        parts += CardExtra.allCases.filter(filters.extras.contains).map(DeckCopy.name)
        return parts.joined(separator: " · ")
    }
}
