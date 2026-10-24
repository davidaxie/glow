import APIClient
import DesignSystem
import SwiftUI

// Owner: C1. What did you notice: who (within my show me), top color, hair and extras. Every part
// can be skipped. The apply button sits at the bottom, under the thumb.

struct NoticeSheet: View {
    /// Genders I may pick from: my show me. With only one, the section is left out.
    let showMe: [Gender]
    let initial: NoticedFilters
    let onApply: (NoticedFilters) -> Void

    @State private var draft: NoticedFilters

    init(showMe: [Gender], initial: NoticedFilters, onApply: @escaping (NoticedFilters) -> Void) {
        self.showMe = showMe
        self.initial = initial
        self.onApply = onApply
        _draft = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                    Text(DeckCopy.noticeTitle)
                        .glowFont(.title)
                        .foregroundStyle(.glowTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(DeckCopy.noticeSubtitle)
                        .glowFont(.callout)
                        .foregroundStyle(.glowTextSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                if showMe.count > 1 {
                    NoticeSection(title: DeckCopy.noticeWho, options: showMe, selection: $draft.genders, id: "who") {
                        NoticeOption(title: DeckCopy.name($0))
                    }
                }
                NoticeSection(title: DeckCopy.noticeTop, options: TopColor.allCases, selection: $draft.topColors, id: "top") {
                    NoticeOption(title: DeckCopy.name($0), swatch: GlowSwatch(rawValue: $0.rawValue))
                }
                NoticeSection(
                    title: DeckCopy.noticeHairLength,
                    options: HairLength.allCases,
                    selection: $draft.hairLengths,
                    id: "hairLength",
                ) {
                    NoticeOption(title: DeckCopy.name($0))
                }
                NoticeSection(title: DeckCopy.noticeHairColor, options: HairColor.allCases, selection: $draft.hairColors, id: "hairColor") {
                    NoticeOption(title: DeckCopy.name($0), swatch: GlowSwatch(rawValue: $0.rawValue))
                }
                NoticeSection(title: DeckCopy.noticeExtras, options: CardExtra.allCases, selection: $draft.extras, id: "extras") {
                    NoticeOption(title: DeckCopy.name($0), systemImage: $0.deckSymbol)
                }
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.xl)
            .padding(.bottom, GlowSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GlowSpacing.xs) {
                Button(DeckCopy.noticeApply(draft.count)) {
                    onApply(draft)
                }
                .buttonStyle(.glowPrimary)
                .accessibilityIdentifier("deck.notice.apply")
                if !draft.isEmpty {
                    Button(DeckCopy.noticeClear) {
                        draft = .none
                    }
                    .buttonStyle(.glowQuiet)
                    .accessibilityIdentifier("deck.notice.clear")
                }
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.top, GlowSpacing.sm)
            .padding(.bottom, GlowSpacing.xs)
            .background(.glowSurface)
        }
        .background(.glowSurface)
        .accessibilityIdentifier("deck.notice")
    }
}

/// How one option looks as a chip.
struct NoticeOption {
    let title: String
    var swatch: GlowSwatch?
    var systemImage: String?
}

/// A titled group of toggle chips. Several can be picked; none means any.
struct NoticeSection<Option: Hashable & RawRepresentable>: View where Option.RawValue == String {
    let title: String
    let options: [Option]
    @Binding var selection: Set<Option>
    let id: String
    let option: (Option) -> NoticeOption

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.sm) {
            Text(title)
                .glowFont(.headline)
                .foregroundStyle(.glowTextPrimary)
                .accessibilityAddTraits(.isHeader)
            GlowFlowLayout {
                ForEach(options, id: \.self) { value in
                    let look = option(value)
                    GlowChip(look.title, systemImage: look.systemImage, swatch: look.swatch, isSelected: selection.contains(value)) {
                        if selection.contains(value) {
                            selection.remove(value)
                        } else {
                            selection.insert(value)
                        }
                    }
                    .accessibilityIdentifier("deck.notice.\(id).\(value.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
