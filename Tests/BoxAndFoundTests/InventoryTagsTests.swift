import Foundation
import Testing
@testable import BoxAndFound

/// The tag bar above the box list: what it counts, and what tapping one does.
private struct TagStub: InventoryReading {
    var allPlaces: [Box] = []

    func households(userID: String) async throws(InventoryFailure) -> [Household] {
        [Household(id: "hh", name: "Home", inviteCode: nil, ownerID: nil)]
    }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        [Room(id: "room-attic", name: "Attic", householdID: "hh")]
    }

    func places(householdID: String) async throws(InventoryFailure) -> [Box] { allPlaces }

    func box(id: String) async throws(InventoryFailure) -> Box { throw InventoryFailure.notFound }
}

@MainActor
@Suite("Inventory tags")
struct InventoryTagsTests {

    private func box(
        _ id: String,
        _ name: String,
        tags: [String] = [],
        type: String = Places.typeBox,
        items: [BoxItem] = []
    ) -> Box {
        Box(
            id: id,
            name: name,
            roomID: "room-attic",
            householdID: "hh",
            items: items,
            tags: tags,
            type: type
        )
    }

    private func presenter(_ places: [Box]) async -> InventoryPresenter {
        let presenter = InventoryPresenter(
            userID: "user-1",
            repository: TagStub(allPlaces: places),
            activeHousehold: ActiveHouseholdStore(
                defaults: UserDefaults(suiteName: "tags-\(UUID().uuidString)")!
            )
        )
        await presenter.appeared()
        return presenter
    }

    private func names(_ state: InventoryViewState) -> [String] {
        guard case .sections(let sections) = state.content else { return [] }
        return sections.flatMap { $0.boxes.map(\.name) }
    }

    @Test("The bar is empty when nothing is tagged")
    func noTags() async {
        let found = await presenter([box("b", "Spare Box")])
        #expect(found.viewState.tags.isEmpty)
    }

    /// Counted per use rather than per box, which is how the web counts them
    /// and what makes the number mean "how much of this tag is about".
    @Test("Every tag in use, counted per use")
    func counts() async {
        let found = await presenter([
            box("b", "Winter Clothes", tags: ["winter"], items: [
                BoxItem(id: "scarf", name: "Scarf", tags: ["winter"]),
            ]),
            box("c", "Tools", tags: ["heavy"]),
        ])

        #expect(found.viewState.tags.map(\.label) == ["heavy", "winter"])
        #expect(found.viewState.tags.first { $0.label == "winter" }?.count == 2)
    }

    /// An item loose in a wardrobe carries tags too, and counting only what is
    /// in boxes would leave it out of the bar it belongs in.
    @Test("Tags on things loose in a container are counted")
    func looseItemTags() async {
        let found = await presenter([
            box("w", "Wardrobe", type: "wardrobe", items: [
                BoxItem(id: "coat", name: "Coat", tags: ["winter"]),
            ]),
            box("b", "Spare Box"),
        ])
        #expect(found.viewState.tags.map(\.label) == ["winter"])
    }

    @Test("Something out of its box is a tag nobody typed")
    func derivedTag() async {
        let found = await presenter([
            box("b", "Winter Clothes", items: [
                BoxItem(id: "scarf", name: "Scarf", isTaken: true),
            ]),
        ])
        let chip = found.viewState.tags.first
        #expect(chip?.label == Tags.taken)
        #expect(chip?.isDerived == true)
    }

    @Test("Tapping a tag narrows the list, and tapping it again clears it")
    func toggling() async {
        let found = await presenter([
            box("b", "Winter Clothes", tags: ["winter"]),
            box("c", "Tools", tags: ["heavy"]),
        ])
        #expect(names(found.viewState).sorted() == ["Tools", "Winter Clothes"])

        found.tagTapped("winter")
        #expect(names(found.viewState) == ["Winter Clothes"])
        #expect(found.viewState.tags.first { $0.label == "winter" }?.isActive == true)

        found.tagTapped("WINTER")
        #expect(names(found.viewState).sorted() == ["Tools", "Winter Clothes"])
    }

    /// Two at once asks whether it means both or either, and neither answer is
    /// guessable from a row of chips.
    @Test("Only one tag filters at a time")
    func oneAtATime() async {
        let found = await presenter([
            box("b", "Winter Clothes", tags: ["winter"]),
            box("c", "Tools", tags: ["heavy"]),
        ])
        found.tagTapped("winter")
        found.tagTapped("heavy")

        #expect(names(found.viewState) == ["Tools"])
        #expect(found.viewState.tags.filter(\.isActive).map(\.label) == ["heavy"])
    }

    @Test("A tag narrows a search rather than replacing it")
    func tagAndSearch() async {
        let found = await presenter([
            box("b", "Winter Clothes", tags: ["winter"]),
            box("c", "Winter Boots", tags: ["heavy"]),
        ])
        found.searchChanged("winter")
        #expect(names(found.viewState).sorted() == ["Winter Boots", "Winter Clothes"])

        found.tagTapped("heavy")
        #expect(names(found.viewState) == ["Winter Boots"])
    }

    /// Naming only one of the two leaves someone clearing a filter that was
    /// not the reason the list is empty.
    @Test("An empty list says which filters emptied it")
    func emptyMessage() async {
        let found = await presenter([box("b", "Winter Clothes", tags: ["winter"])])

        found.tagTapped("winter")
        found.searchChanged("tools")
        guard case .empty(let message) = found.viewState.content else {
            Issue.record("Expected an empty list")
            return
        }
        #expect(message.contains("winter"))
        #expect(message.contains("tools"))
    }

    /// The bar has to survive a filter that empties the list, or there is no
    /// way left to clear it.
    @Test("The bar stays when the tag filters everything out")
    func barSurvivesAnEmptyList() async {
        let found = await presenter([
            // Tagged on something loose in a container, so no box carries it.
            box("w", "Wardrobe", type: "wardrobe", items: [
                BoxItem(id: "coat", name: "Coat", tags: ["winter"]),
            ]),
            box("b", "Spare Box"),
        ])
        found.tagTapped("winter")

        guard case .empty = found.viewState.content else {
            Issue.record("Expected the list to be filtered empty")
            return
        }
        #expect(found.viewState.tags.map(\.label) == ["winter"])
    }
}
