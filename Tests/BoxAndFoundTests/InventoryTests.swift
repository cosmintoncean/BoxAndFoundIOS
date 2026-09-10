import Foundation
import Testing
@testable import BoxAndFound

@Suite("Inventory models")
struct InventoryModelTests {

    @Test("Items are ordered on the way in, so no reader has to remember to")
    func itemsAreOrderedAtConstruction() {
        let box = Box(id: "b", items: [
            BoxItem(id: "3", name: "Gloves", position: 2),
            BoxItem(id: "1", name: "Scarf", position: 0),
            BoxItem(id: "2", name: "Hat", position: 1),
        ])
        #expect(box.items.map(\.name) == ["Scarf", "Hat", "Gloves"])
    }

    /// PostgREST returns embedded rows in no guaranteed order, so two reads of
    /// the same box can arrive differently. Without a tiebreak the list would
    /// visibly reshuffle.
    @Test("Equal positions fall back to name, so the list cannot reshuffle")
    func nameBreaksPositionTies() {
        let box = Box(id: "b", items: [
            BoxItem(id: "1", name: "banana", position: 0),
            BoxItem(id: "2", name: "Apple", position: 0),
        ])
        #expect(box.items.map(\.name) == ["Apple", "banana"])
    }

    @Test("An unnamed item sorts last within its position")
    func unnamedItemsSortLast() {
        let box = Box(id: "b", items: [
            BoxItem(id: "1", name: nil, position: 0),
            BoxItem(id: "2", name: "Anything", position: 0),
        ])
        #expect(box.items.map(\.id) == ["2", "1"])
    }

    @Test("Owners are recognised by field, since they are not membership rows")
    func ownership() {
        let household = Household(id: "h", name: "Home", inviteCode: nil, ownerID: "user-1")
        #expect(household.isOwned(by: "user-1"))
        #expect(!household.isOwned(by: "user-2"))
    }

    @Test("The twelve icon keys match the web client's picker, in its order")
    func iconKeysAreTheContract() {
        #expect(BoxIcons.keys == [
            "box", "casserole", "bag", "backpack", "suitcase", "cardbox",
            "basket", "bucket", "cabinet", "folder", "gift", "toy",
        ])
        #expect(BoxIcons.defaultKey == "box")
    }

    @Test("An icon key another client invented falls back rather than breaking")
    func unknownIconFallsBack() {
        #expect(BoxIcons.normalise("crate") == "box")
        #expect(BoxIcons.normalise(nil) == "box")
        #expect(BoxIcons.normalise("gift") == "gift")
    }
}

@Suite("Remembered household")
struct ActiveHouseholdStoreTests {

    private func store() -> (ActiveHouseholdStore, UserDefaults) {
        // A throwaway suite name keeps each test off the real preferences and
        // out of each other's way.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return (ActiveHouseholdStore(defaults: defaults), defaults)
    }

    private func household(_ id: String) -> Household {
        Household(id: id, name: id, inviteCode: nil, ownerID: nil)
    }

    @Test("Reopens the household you were last in")
    func remembers() {
        let (store, _) = store()
        store.set("h2")
        #expect(store.resolve(from: [household("h1"), household("h2")])?.id == "h2")
    }

    @Test("Falls back to the first when nothing is remembered")
    func fallsBackToFirst() {
        let (store, _) = store()
        #expect(store.resolve(from: [household("h1"), household("h2")])?.id == "h1")
    }

    /// The remembered id is a hint, not an authority. Being removed from a
    /// household must not strand you on a screen you can no longer read.
    @Test("A household you can no longer see is ignored, not obeyed")
    func staleIdIsIgnored() {
        let (store, _) = store()
        store.set("h-removed")
        #expect(store.resolve(from: [household("h1")])?.id == "h1")
    }

    @Test("No households means nothing to open")
    func emptyMeansNil() {
        let (store, _) = store()
        store.set("h1")
        #expect(store.resolve(from: []) == nil)
    }

    @Test("Clearing forgets")
    func clears() {
        let (store, _) = store()
        store.set("h2")
        store.clear()
        #expect(store.activeHouseholdID == nil)
    }
}
