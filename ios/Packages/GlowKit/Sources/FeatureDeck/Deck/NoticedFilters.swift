import APIClient
import Foundation

// Owner: C1. What the person noticed, from the What did you notice sheet.

/// What I noticed. Every part is optional, and an empty set means any (contract: `DeckFilters`).
/// A card fits when each picked attribute is one of the picked values and it has every picked extra.
struct NoticedFilters: Hashable, Sendable {
    var genders: Set<Gender> = []
    var topColors: Set<TopColor> = []
    var hairLengths: Set<HairLength> = []
    var hairColors: Set<HairColor> = []
    var extras: Set<CardExtra> = []

    static let none = NoticedFilters()

    /// Nothing picked: everyone who fits me.
    var isEmpty: Bool {
        count == 0
    }

    /// How many values are picked across every part.
    var count: Int {
        genders.count + topColors.count + hairLengths.count + hairColors.count + extras.count
    }

    /// How many parts have something picked (for analytics: never the values).
    var partsPicked: Int {
        [!genders.isEmpty, !topColors.isEmpty, !hairLengths.isEmpty, !hairColors.isEmpty, !extras.isEmpty].count(where: \.self)
    }

    /// Keeps only genders I'm allowed to see. The deck already applies show me on the server; this
    /// only stops the sheet offering or sending a gender outside it.
    func limited(toShowMe showMe: Set<Gender>) -> NoticedFilters {
        var copy = self
        copy.genders = genders.intersection(showMe)
        return copy
    }

    /// The contract's filters, with lists in a stable order (the enum's order) and empty parts left out.
    var contract: Components.Schemas.DeckFilters {
        Components.Schemas.DeckFilters(
            gender: Self.list(genders),
            topColor: Self.list(topColors),
            hairLength: Self.list(hairLengths),
            hairColor: Self.list(hairColors),
            extras: Self.list(extras),
        )
    }

    /// Whether a card with these tags (and this gender, which only the server and fixtures know)
    /// fits. The server's `get_deck` is the real rule; this mirrors it for fixtures and tests.
    func matches(_ tags: CardTags, gender: Gender?) -> Bool {
        if !genders.isEmpty {
            guard let gender, genders.contains(gender) else { return false }
        }
        if !topColors.isEmpty, !topColors.contains(tags.topColor) {
            return false
        }
        if !hairLengths.isEmpty {
            guard let length = tags.hairLength, hairLengths.contains(length) else { return false }
        }
        if !hairColors.isEmpty {
            guard let color = tags.hairColor, hairColors.contains(color) else { return false }
        }
        return extras.isSubset(of: Set(tags.extras))
    }

    private static func list<Value: CaseIterable & Hashable>(_ set: Set<Value>) -> [Value]? {
        set.isEmpty ? nil : Value.allCases.filter(set.contains)
    }
}
