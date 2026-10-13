import Foundation
import Testing
@testable import BoxAndFound

/// The tag rules, ported from the Android client's `TagsTest`. All three
/// clients write the same `text[]`, so a tag typed on a phone and a tag typed
/// in a browser have to normalise identically — these are the web's
/// `normalizeTags` in another language.
@Suite("Tags")
struct TagsTests {

    private func box(
        _ id: String,
        tags: [String] = [],
        type: String = Places.typeBox,
        items: [BoxItem] = []
    ) -> Box {
        Box(id: id, name: id, householdID: "hh", items: items, tags: tags, type: type)
    }

    private func item(
        _ id: String,
        tags: [String] = [],
        taken: Bool = false
    ) -> BoxItem {
        BoxItem(id: id, name: id, isTaken: taken, tags: tags)
    }

    // MARK: - Normalising

    @Test("Trims, and drops the blanks")
    func trims() {
        #expect(Tags.normalise(["  fragile  ", "", "   "]) == ["fragile"])
    }

    @Test("A leading hash is decoration, not part of the tag")
    func hash() {
        #expect(Tags.normalise(["#winter"]) == ["winter"])
        #expect(Tags.normalise(["## winter"]) == ["winter"])
    }

    @Test("The same tag in two cases is one tag, spelled as first written")
    func caseFolding() {
        #expect(Tags.normalise(["Fragile", "fragile", "FRAGILE"]) == ["Fragile"])
    }

    @Test("A tag is cut to the limit rather than refused")
    func length() {
        let long = String(repeating: "a", count: Tags.maxLength + 10)
        #expect(Tags.normalise([long]) == [String(repeating: "a", count: Tags.maxLength)])
    }

    @Test("No more than the cap, and the first ones win")
    func count() {
        let many = (1...(Tags.maxCount + 5)).map { "tag\($0)" }
        let kept = Tags.normalise(many)
        #expect(kept.count == Tags.maxCount)
        #expect(kept.first == "tag1")
    }

    @Test("A comma separates one typed tag from the next")
    func typed() {
        #expect(Tags.normalise(typed: "fragile, winter ,  #lend out") == ["fragile", "winter", "lend out"])
        #expect(Tags.normalise(typed: "").isEmpty)
    }

    // MARK: - Filtering

    @Test("A box answers for its items")
    func boxAnswersForItems() {
        let tagged = box("b", items: [item("scarf", tags: ["winter"])])
        #expect(Tags.boxHasTag(tagged, tag: "winter"))
        #expect(Tags.boxHasTag(box("b", tags: ["winter"]), tag: "winter"))
        #expect(!Tags.boxHasTag(box("b"), tag: "winter"))
    }

    @Test("No tag at all matches everything, which is what no filter means")
    func noFilter() {
        #expect(Tags.boxHasTag(box("b"), tag: nil))
        #expect(Tags.boxHasTag(box("b"), tag: "  "))
    }

    @Test("The taken tag filters like any other")
    func takenFilters() {
        let out = box("b", items: [item("scarf", taken: true)])
        #expect(Tags.boxHasTag(out, tag: Tags.taken))
        #expect(Tags.boxHasTag(out, tag: "TAKEN"))
        #expect(!Tags.boxHasTag(box("b", items: [item("scarf")]), tag: Tags.taken))
    }

    // MARK: - Counting

    @Test("Counted every time it is used, as the web counts it")
    func perOccurrence() {
        let counted = Tags.usageCounts([
            box("b", tags: ["winter"], items: [
                item("scarf", tags: ["winter"]),
                item("gloves", tags: ["winter"]),
            ]),
        ])
        #expect(counted == [TagCount(label: "winter", count: 3)])
    }

    @Test("Listed alphabetically, not by how many carry them")
    func ordering() {
        let counted = Tags.usageCounts([
            box("b", tags: ["zebra", "zebra-two", "apple"], items: [
                item("i", tags: ["apple"]),
            ]),
        ])
        #expect(counted.map(\.label) == ["apple", "zebra", "zebra-two"])
    }

    @Test("Something out of its box is a tag nobody typed")
    func derived() {
        let counted = Tags.usageCounts([
            box("b", items: [item("scarf", taken: true), item("gloves", taken: true)]),
        ])
        #expect(counted == [TagCount(label: Tags.taken, count: 2)])
        #expect(Tags.isDerived(Tags.taken))
        #expect(!Tags.isDerived("winter"))
    }

    /// The derived tag leads the list: being out of place is a state to
    /// notice, not a label anyone chose.
    @Test("The derived tag comes first however it sorts")
    func derivedLeads() {
        let counted = Tags.usageCounts([
            box("b", tags: ["apple"], items: [item("scarf", taken: true)]),
        ])
        #expect(counted.map(\.label) == [Tags.taken, "apple"])
    }

    @Test("An item loose in a container carries tags too")
    func looseItemsCount() {
        let counted = Tags.usageCounts([
            box("w", type: "wardrobe", items: [item("torch", tags: ["camping"])]),
        ])
        #expect(counted == [TagCount(label: "camping", count: 1)])
    }
}
