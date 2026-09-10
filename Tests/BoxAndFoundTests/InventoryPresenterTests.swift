import Foundation
import Testing
@testable import BoxAndFound

/// A stand-in for the real reads, so the presenter's own logic — resolving the
/// household, grouping, searching, deciding what "empty" means — can be run
/// against fixed data with nothing on the network.
private struct StubInventory: InventoryReading {
    var allHouseholds: [Household] = []
    var allRooms: [Room] = []
    var allBoxes: [Box] = []
    var singleBox: Box?
    var failure: InventoryFailure?

    func households(userID: String) async throws(InventoryFailure) -> [Household] {
        if let failure { throw failure }
        return allHouseholds
    }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        if let failure { throw failure }
        return allRooms
    }

    func boxes(householdID: String) async throws(InventoryFailure) -> [Box] {
        if let failure { throw failure }
        return allBoxes.filter { $0.householdID == nil || $0.householdID == householdID }
    }

    func box(id: String) async throws(InventoryFailure) -> Box {
        if let failure { throw failure }
        guard let singleBox else { throw InventoryFailure.notFound }
        return singleBox
    }
}

private func household(_ id: String, _ name: String) -> Household {
    Household(id: id, name: name, inviteCode: nil, ownerID: nil)
}

private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID().uuidString)")!
}

@Suite("Inventory presenter")
@MainActor
struct InventoryPresenterTests {

    private func makePresenter(
        _ stub: StubInventory,
        defaults: UserDefaults? = nil
    ) -> InventoryPresenter {
        InventoryPresenter(
            userID: "user-1",
            repository: stub,
            activeHousehold: ActiveHouseholdStore(defaults: defaults ?? emptyDefaults())
        )
    }

    @Test("Opens on a spinner rather than an empty household")
    func startsLoading() {
        #expect(makePresenter(StubInventory()).viewState.content == .loading)
    }

    @Test("Boxes arrive grouped by room, with counts already worded")
    func loadsAndGroups() async {
        let stub = StubInventory(
            allHouseholds: [household("h1", "Home")],
            allRooms: [Room(id: "r1", name: "Garage", householdID: "h1")],
            allBoxes: [
                Box(id: "b1", name: "Tools", location: "Shelf", roomID: "r1", items: [
                    BoxItem(id: "i1", name: "Hammer"),
                    BoxItem(id: "i2", name: "Saw", isTaken: true),
                ]),
                Box(id: "b2", name: "Spare"),
            ]
        )
        let presenter = makePresenter(stub)
        await presenter.appeared()

        let state = presenter.viewState
        #expect(state.title == "Home")
        #expect(!state.isHouseholdSwitcherVisible)
        #expect(state.isSearchVisible)

        guard case .sections(let sections) = state.content else {
            Issue.record("Expected sections, got \(state.content)")
            return
        }
        #expect(sections.map(\.title) == ["Garage", "No room"])

        let tools = sections[0].boxes[0]
        #expect(tools.name == "Tools")
        #expect(tools.itemCount == "2 items")
        #expect(tools.takenNote == "1 taken")
        #expect(tools.location == "Shelf")
        #expect(tools.matchNote == nil)
    }

    @Test("A household with no boxes says so, and hides the search field")
    func emptyHousehold() async {
        let presenter = makePresenter(StubInventory(allHouseholds: [household("h1", "Home")]))
        await presenter.appeared()

        #expect(presenter.viewState.content == .empty(message: InventoryCopy.noBoxes))
        #expect(!presenter.viewState.isSearchVisible)
    }

    @Test("No households at all is a different message from no boxes")
    func noHouseholds() async {
        let presenter = makePresenter(StubInventory())
        await presenter.appeared()
        #expect(presenter.viewState.content == .empty(message: InventoryCopy.noHouseholds))
    }

    @Test("A failed read offers a retry rather than an empty household")
    func failureIsNotEmptiness() async {
        let presenter = makePresenter(StubInventory(failure: .network))
        await presenter.appeared()

        #expect(presenter.viewState.content
            == .failed(message: InventoryCopy.message(for: .network)))
        #expect(!presenter.viewState.isSearchVisible)
    }

    @Test("Searching narrows the list and says why a box survived")
    func searchExplainsItself() async {
        let stub = StubInventory(
            allHouseholds: [household("h1", "Home")],
            allBoxes: [
                Box(id: "b1", name: "Winter", items: [BoxItem(id: "i1", name: "Gloves")]),
                Box(id: "b2", name: "Books"),
            ]
        )
        let presenter = makePresenter(stub)
        await presenter.appeared()
        presenter.searchChanged("glov")

        guard case .sections(let sections) = presenter.viewState.content else {
            Issue.record("Expected sections")
            return
        }
        #expect(sections.flatMap(\.boxes).map(\.id) == ["b1"])
        #expect(sections[0].boxes[0].matchNote == "Matches: Gloves")
    }

    @Test("A box found by its own name does not explain itself twice")
    func nameMatchNeedsNoNote() async {
        let stub = StubInventory(
            allHouseholds: [household("h1", "Home")],
            allBoxes: [Box(id: "b1", name: "Winter", items: [BoxItem(id: "i1", name: "Winter hat")])]
        )
        let presenter = makePresenter(stub)
        await presenter.appeared()
        presenter.searchChanged("winter")

        guard case .sections(let sections) = presenter.viewState.content else {
            Issue.record("Expected sections")
            return
        }
        #expect(sections[0].boxes[0].matchNote == nil)
    }

    @Test("A search that matches nothing says what it was looking for")
    func noResults() async {
        let stub = StubInventory(
            allHouseholds: [household("h1", "Home")],
            allBoxes: [Box(id: "b1", name: "Winter")]
        )
        let presenter = makePresenter(stub)
        await presenter.appeared()
        presenter.searchChanged("zzz")

        #expect(presenter.viewState.content == .empty(message: InventoryCopy.noResults(for: "zzz")))
    }

    @Test("More than one household shows the switcher")
    func switcherAppears() async {
        let stub = StubInventory(allHouseholds: [household("h1", "Home"), household("h2", "Studio")])
        let presenter = makePresenter(stub)
        await presenter.appeared()

        #expect(presenter.viewState.isHouseholdSwitcherVisible)
        #expect(presenter.viewState.households.map(\.name) == ["Home", "Studio"])
    }

    @Test("Switching household clears the search and remembers the choice")
    func switchingHousehold() async {
        let defaults = emptyDefaults()
        let stub = StubInventory(
            allHouseholds: [household("h1", "Home"), household("h2", "Studio")],
            allBoxes: [Box(id: "b1", name: "Winter", householdID: "h1")]
        )
        let presenter = makePresenter(stub, defaults: defaults)
        await presenter.appeared()
        presenter.searchChanged("winter")

        await presenter.householdSelected("h2")

        #expect(presenter.viewState.activeHouseholdID == "h2")
        #expect(presenter.viewState.searchTerm.isEmpty)
        #expect(ActiveHouseholdStore(defaults: defaults).activeHouseholdID == "h2")
    }

    @Test("The household you were last in is the one that reopens")
    func reopensRemembered() async {
        let defaults = emptyDefaults()
        ActiveHouseholdStore(defaults: defaults).set("h2")

        let stub = StubInventory(allHouseholds: [household("h1", "Home"), household("h2", "Studio")])
        let presenter = makePresenter(stub, defaults: defaults)
        await presenter.appeared()

        #expect(presenter.viewState.title == "Studio")
    }

    @Test("Signing out forgets the household, so the next account starts clean")
    func signOutForgets() async {
        let defaults = emptyDefaults()
        let store = ActiveHouseholdStore(defaults: defaults)
        store.set("h1")

        final class Flag { var raised = false }
        let flag = Flag()
        let presenter = InventoryPresenter(
            userID: "user-1",
            repository: StubInventory(),
            activeHousehold: store,
            signOut: { flag.raised = true }
        )
        await presenter.signOutTapped()

        #expect(flag.raised)
        #expect(store.activeHouseholdID == nil)
    }
}

@Suite("Box detail presenter")
@MainActor
struct BoxDetailPresenterTests {

    @Test("Opens with the title the list already knew, not a blank bar")
    func borrowsTheTitle() {
        let presenter = BoxDetailPresenter(
            boxID: "b1",
            title: "Winter Clothes",
            userID: "user-1",
            reader: StubInventory()
        )
        #expect(presenter.viewState.title == "Winter Clothes")
        #expect(presenter.viewState.content == .loading)
    }

    @Test("Quantities of one are left off, and taken items are marked")
    func itemPresentation() async {
        let stub = StubInventory(singleBox: Box(id: "b1", name: "Winter", location: "Attic", items: [
            BoxItem(id: "i1", name: "Scarf", quantity: 1, position: 0),
            BoxItem(id: "i2", name: "Gloves", quantity: 3, position: 1, isTaken: true),
        ]))
        let presenter = BoxDetailPresenter(
            boxID: "b1", title: "Winter", userID: "user-1", reader: stub
        )
        await presenter.appeared()

        guard case .loaded(let box) = presenter.viewState.content else {
            Issue.record("Expected a loaded box")
            return
        }
        #expect(box.itemCount == "2 items")
        #expect(box.takenNote == "1 taken")
        #expect(box.location == "Attic")
        #expect(box.items.map(\.quantity) == [nil, "×3"])
        #expect(box.items.map(\.isTaken) == [false, true])
        #expect(box.emptyMessage == nil)
    }

    @Test("An empty box says so instead of showing an empty list")
    func emptyBox() async {
        let stub = StubInventory(singleBox: Box(id: "b1", name: "Spare"))
        let presenter = BoxDetailPresenter(
            boxID: "b1", title: "Spare", userID: "user-1", reader: stub
        )
        await presenter.appeared()

        guard case .loaded(let box) = presenter.viewState.content else {
            Issue.record("Expected a loaded box")
            return
        }
        #expect(box.emptyMessage == InventoryCopy.emptyBox)
        #expect(box.items.isEmpty)
    }

    @Test("A box that is gone says that, not something went wrong")
    func missingBox() async {
        let presenter = BoxDetailPresenter(
            boxID: "b1",
            title: "Winter",
            userID: "user-1",
            reader: StubInventory(failure: .notFound)
        )
        await presenter.appeared()

        #expect(presenter.viewState.content
            == .failed(message: InventoryCopy.message(for: .notFound)))
    }
}
