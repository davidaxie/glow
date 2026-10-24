import SwiftUI

// Owner: B6. A grid of chips for picking tags: the outfit tags at check-in, and the "What did you
// notice" filters on the deck. Rows wrap, so nothing clips at large text sizes.
//
//     GlowTagPicker("Top color", options: TopColor.allCases, selection: $topColor) { color in
//         GlowTag(color.displayName, swatch: GlowSwatch(rawValue: color.rawValue))
//     }
//     GlowTagPicker("Extras", options: CardExtra.allCases, selection: $extras) { extra in
//         GlowTag(extra.displayName, systemImage: extra.symbol)
//     }

/// How one option looks in a tag picker or on a card.
public struct GlowTag: Hashable, Sendable {
    public let title: String
    public let systemImage: String?
    public let swatch: GlowSwatch?

    /// - Parameter title: already localized.
    public init(_ title: String, systemImage: String? = nil, swatch: GlowSwatch? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.swatch = swatch
    }
}

/// A titled group of chips. Pick one (`selection: Binding<Option?>`) or several
/// (`selection: Binding<Set<Option>>`, with an optional limit).
public struct GlowTagPicker<Option: Hashable>: View {
    private let title: Text?
    private let options: [Option]
    private let tag: (Option) -> GlowTag
    let isSelected: (Option) -> Bool
    let isAvailable: (Option) -> Bool
    let toggle: (Option) -> Void

    /// Pick several. Once `limit` are picked, the rest are disabled until one is unpicked.
    public init(
        _ title: LocalizedStringKey? = nil,
        options: [Option],
        selection: Binding<Set<Option>>,
        limit: Int? = nil,
        tag: @escaping (Option) -> GlowTag,
    ) {
        self.title = title.map { Text($0) }
        self.options = options
        self.tag = tag
        isSelected = { selection.wrappedValue.contains($0) }
        isAvailable = { option in
            guard let limit else { return true }
            return selection.wrappedValue.contains(option) || selection.wrappedValue.count < limit
        }
        toggle = { option in
            if selection.wrappedValue.contains(option) {
                selection.wrappedValue.remove(option)
            } else if limit.map({ selection.wrappedValue.count < $0 }) ?? true {
                selection.wrappedValue.insert(option)
            }
        }
    }

    /// Pick one. Tapping the picked option again clears it when `allowsNone` is true.
    public init(
        _ title: LocalizedStringKey? = nil,
        options: [Option],
        selection: Binding<Option?>,
        allowsNone: Bool = false,
        tag: @escaping (Option) -> GlowTag,
    ) {
        self.title = title.map { Text($0) }
        self.options = options
        self.tag = tag
        isSelected = { selection.wrappedValue == $0 }
        isAvailable = { _ in true }
        toggle = { option in
            if selection.wrappedValue == option {
                if allowsNone {
                    selection.wrappedValue = nil
                }
            } else {
                selection.wrappedValue = option
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.sm) {
            if let title {
                title
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            GlowFlowLayout {
                ForEach(options, id: \.self) { option in
                    let tag = tag(option)
                    GlowChip(tag.title, systemImage: tag.systemImage, swatch: tag.swatch, isSelected: isSelected(option)) {
                        toggle(option)
                    }
                    .disabled(!isAvailable(option))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
