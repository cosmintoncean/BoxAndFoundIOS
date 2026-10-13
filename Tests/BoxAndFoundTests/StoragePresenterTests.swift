import Foundation
import Testing
@testable import BoxAndFound

/// Fixed storage, so one level of the tree can be rendered with nothing on the
/// network.
private struct StubStorage: InventoryReading {
    var allPlaces: [Box] = []
    var allRooms: [Room] = []
    var failure: InventoryFailure?

    func households(userID: String) async throws(InventoryFailure) -> [Household] { [] }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        if let failure { throw failure }
        return allRooms
    }

    func places(householdID: String) async throws(InventoryFailure) -> [Box] {
        if let failure { throw failure }
        return allPlaces
    }

    func box(id: String) async throws(InventoryFailure) -> Box {
        throw InventoryFailure.notFound
    }
}

@MainActor
@Suite("Storage presenter")
struct StoragePresenterTests {

    private let householdID = "hh"

    private func place(
        _ id: String,
        name: String,
        type: String = Places.typeBox,
        parentID: String? = nil,
        roomID: String? = "room-attic",
        items: [BoxItem] = []
    ) -> Box {
        Box(
            id: id,
            name: name,
            icon: "cardbox",
            roomID: roomID,
            householdID: "hh",
            items: items,
            type: type,
            parentID: parentID
        )
    }

    /// Attic → Wardrobe → Winter Clothes, a box straight in the room, and a
    /// stepladder leaning against the wall.
    private var attic: [Box] {
        [
            place("wardrobe", name: "Wardrobe", type: "wardrobe", items: [
                BoxItem(id: "coat", name: "Winter coat"),
            ]),
            place("winter", name: "Winter Clothes", parentID: "wardrobe", items: [
                BoxItem(id: "scarf", name: "Scarf"),
                BoxItem(id: "gloves", name: "Gloves"),
            ]),
            place("spare", name: "Spare Box"),
            place("holder", name: "Attic", type: Places.typeRoomItems, items: [
                BoxItem(id: "stepladder", name: "Stepladder", quantity: 2),
            ]),
        ]
    }

    private let rooms = [Room(id: "room-attic", name: "Attic", householdID: "hh")]

    private func presenter(
        _ target: StorageTarget,
        places: [Box],
        failure: InventoryFailure? = nil
    ) async -> StoragePresenter {
        let presenter = StoragePresenter(
            target: target,
            householdID: householdID,
            repository: StubStorage(allPlaces: places, allRooms: rooms, failure: failure)
        )
        await presenter.appeared()
        return presenter
    }

    private func contents(_ state: StorageViewState) -> StorageViewState.Contents? {
        guard case .contents(let contents) = state.content else { return nil }
        return contents
    }

    // MARK: - A room's own level

    @Test("A room shows what is in it, and not what is inside those things")
    func roomLevel() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic
        )
        let found = contents(presenter.viewState)

        #expect(found?.containers.map(\.name) == ["Wardrobe"])
        // Winter Clothes is in the wardrobe, so it is not at this level.
        #expect(found?.boxes.map(\.name) == ["Spare Box"])
        #expect(presenter.viewState.title == "Attic")
    }

    /// A wardrobe holding one box of two things reads as one box, not two
    /// things — plus the coat, which nothing else accounts for.
    @Test("A container says what is inside it at every depth")
    func containerCounts() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic
        )
        #expect(contents(presenter.viewState)?.containers.first?.detail == "1 box · 1 loose")
    }

    @Test("A box says how many things are in it")
    func boxCount() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic
        )
        #expect(contents(presenter.viewState)?.boxes.first?.detail == "Empty")
    }

    /// The holder is an implementation detail of the schema; on screen those
    /// items are simply in the room.
    @Test("A room's loose items come from its hidden holder")
    func looseItemsOfARoom() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic
        )
        let found = contents(presenter.viewState)

        #expect(found?.looseItems.map(\.name) == ["Stepladder"])
        #expect(found?.looseItems.first?.quantity == "×2")
        // And it is never offered as a thing to open.
        #expect(found?.containers.contains { $0.name == "Attic" } == false)
    }

    @Test("A room with nothing in it says so once")
    func emptyRoom() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: []
        )
        #expect(contents(presenter.viewState)?.emptyMessage == StorageCopy.emptyRoom)
    }

    // MARK: - Inside a container

    @Test("A container shows its own contents and is titled after itself")
    func containerLevel() async {
        let presenter = await presenter(.container(id: "wardrobe"), places: attic)
        let found = contents(presenter.viewState)

        #expect(presenter.viewState.title == "Wardrobe")
        #expect(found?.boxes.map(\.name) == ["Winter Clothes"])
        #expect(found?.containers.isEmpty == true)
        // Its own items are loose in it.
        #expect(found?.looseItems.map(\.name) == ["Winter coat"])
    }

    @Test("The path says where this sits, without repeating the title")
    func path() async {
        let presenter = await presenter(.container(id: "wardrobe"), places: attic)
        #expect(contents(presenter.viewState)?.path == ["Attic"])
    }

    @Test("A room's own level needs no path, because the title is the path")
    func noPathAtTheTop() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic
        )
        #expect(contents(presenter.viewState)?.path.isEmpty == true)
    }

    /// The message belongs before the attempt, not after the server's refusal.
    @Test("The last level that can hold a container says so")
    func depthNote() async {
        var deep: [Box] = []
        var parent: String?
        for level in 0..<Places.maxDepth {
            let id = "level-\(level)"
            deep.append(place(id, name: id, type: "shelf", parentID: parent))
            parent = id
        }
        let shallow = await presenter(.container(id: "level-0"), places: deep)
        #expect(contents(shallow.viewState)?.depthNote == nil)

        let deepest = await presenter(
            .container(id: "level-\(Places.maxDepth - 1)"),
            places: deep
        )
        #expect(contents(deepest.viewState)?.depthNote != nil)
    }

    // MARK: -

    @Test("A failed read says so rather than showing an empty room")
    func failure() async {
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: attic,
            failure: .network
        )
        guard case .failed(let message) = presenter.viewState.content else {
            Issue.record("Expected a failure")
            return
        }
        #expect(message == InventoryCopy.message(for: .network))
    }
}
