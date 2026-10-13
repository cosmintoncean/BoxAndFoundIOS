import Foundation

/// Free-form labels on a box or on one item inside it — "fragile", "winter",
/// "lend out".
///
/// Deliberately not an entity: there is no tag row anywhere, no colour and no
/// ownership, just text repeated on everything that carries it. That is the
/// web client's model (see `MIGRATION_tags.sql`, where it is a `text[]` on the
/// row), and the rules below are its `normalizeTags` to the letter — all three
/// clients write the same column, so a tag typed on a phone and a tag typed in
/// a browser have to come out identical.
enum Tags {

    /// Long enough for "needs new batteries", short enough to stay a label.
    static let maxLength = 24

    /// Past a handful they stop being labels and start being a second name.
    static let maxCount = 8

    /// One tag nobody types and nothing stores: whether something in here is
    /// out of its box.
    ///
    /// Read off the items on every pass, so a box can never disagree with what
    /// is actually out of it, and filterable like any other tag. A real tag
    /// someone types as "taken" folds into the same filter, which is the
    /// behaviour you would want anyway.
    static let taken = "taken"

    /// Trimmed, stripped of a leading #, capped, and de-duplicated without
    /// regard to case — "Fragile" and "fragile" are one tag, and the first
    /// spelling is the one kept.
    static func normalise(_ tags: [String]) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for entry in tags {
            let withoutHash = entry.trimmed.drop { $0 == "#" }
            let tag = String(
                withoutHash.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength)
            )
            if tag.isEmpty { continue }
            guard seen.insert(tag.lowercased()).inserted else { continue }
            out.append(tag)
            if out.count >= maxCount { break }
        }
        return out
    }

    /// What someone typed into a field, where a comma separates one from the
    /// next.
    static func normalise(typed: String) -> [String] {
        normalise(typed.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
    }

    /// Case-insensitive, because that is how they are de-duplicated.
    static func carries(_ tags: [String], _ tag: String) -> Bool {
        normalise(tags).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// A box answers for its items too: a tag put on one thing inside a box is
    /// still a reason to show that box when the tag is tapped.
    static func boxHasTag(_ box: Box, tag: String?) -> Bool {
        guard let tag, !tag.trimmed.isEmpty else { return true }
        if tag.caseInsensitiveCompare(taken) == .orderedSame {
            return box.items.contains(where: \.isTaken)
        }
        return carries(box.tags, tag) || box.items.contains { carries($0.tags, tag) }
    }

    /// True for the tag nothing stores, which is shown apart from the rest.
    static func isDerived(_ tag: String) -> Bool {
        tag.caseInsensitiveCompare(taken) == .orderedSame
    }

    /// Every tag in use, with how many times it is used.
    ///
    /// Per occurrence, as the web counts: a tag on a box and on two of its
    /// items reads 3. Deliberately not the number of results tapping it gives,
    /// since the filter works on boxes — it is how much of that tag is about.
    ///
    /// Ordered by name, not by count, because a bar that reorders itself as
    /// things are tagged has to be re-read every time. The derived tag leads
    /// it: something being out of place is a state to notice rather than a
    /// label anyone chose.
    ///
    /// `places` is everything that holds something, not only the boxes: an
    /// item loose in a container carries tags too.
    static func usageCounts(_ places: [Box]) -> [TagCount] {
        var byKey: [String: TagCount] = [:]

        func add(_ tag: String) {
            let key = tag.lowercased()
            if let existing = byKey[key] {
                byKey[key] = TagCount(label: existing.label, count: existing.count + 1)
            } else {
                byKey[key] = TagCount(label: tag, count: 1)
            }
        }

        for place in places {
            for tag in normalise(place.tags) { add(tag) }
            for item in place.items {
                for tag in normalise(item.tags) { add(tag) }
            }
            // One for each thing that is out, not one for the box holding it.
            for _ in place.items.filter(\.isTaken) { add(taken) }
        }

        return byKey.values.sorted { lhs, rhs in
            let lhsRank = isDerived(lhs.label) ? 0 : 1
            let rhsRank = isDerived(rhs.label) ? 0 : 1
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.label.lowercased() < rhs.label.lowercased()
        }
    }
}

/// One tag and how many times it is used.
struct TagCount: Equatable, Identifiable, Sendable {
    let label: String
    let count: Int

    var id: String { label.lowercased() }
}
