import Foundation
import Testing
@testable import BoxAndFound

/// Records what was written rather than writing it.
///
/// `@unchecked Sendable` on the same terms as `BoxEditorPresenterTests`: plain
/// mutable state, read only from the main actor the tests run on.
private final class StubWriter: InventoryWriting, @unchecked Sendable {
    struct CreatedContainer: Equatable {
        let name: String
        let type: String
        let roomID: String?
        let parentID: String?
    }

    var createdContainers: [CreatedContainer] = []
    var itemPlans: [(boxID: String, plan: ItemSyncPlan)] = []
    var deletedContainers: [String] = []
    var moves: [(id: String, parentID: String?, roomID: String?)] = []
    var failure: InventoryFailure?

    /// What `createContainer` hands back, so a test can follow what the item
    /// was then written to.
    var newContainerID = "made"

    func createRoom(householdID: String, name: String) async throws(InventoryFailure) -> Room {
        Room(id: "room", name: name, householdID: householdID)
    }

    func deleteRoom(id: String) async throws(InventoryFailure) {}

    func createBox(
        householdID: String,
        name: String,
        icon: String,
        location: String?,
        roomID: String?,
        imageURL: String?
    ) async throws(InventoryFailure) -> Box {
        Box(id: "box", name: name)
    }

    func updateBox(id: String, changes: BoxChanges) async throws(InventoryFailure) {}

    func deleteBox(id: String) async throws(InventoryFailure) {}

    func createContainer(
        householdID: String,
        name: String,
        type: String,
        roomID: String?,
        parentID: String?
    ) async throws(InventoryFailure) -> Box {
        if let failure { throw failure }
        createdContainers.append(
            CreatedContainer(name: name, type: type, roomID: roomID, parentID: parentID)
        )
        return Box(
            id: newContainerID,
            name: name,
            roomID: roomID,
            type: type,
            parentID: parentID
        )
    }

    func movePlace(id: String, parentID: String?, roomID: String?) async throws(InventoryFailure) {
        if let failure { throw failure }
        moves.append((id, parentID, roomID))
    }

    func deleteContainer(id: String) async throws(InventoryFailure) {
        if let failure { throw failure }
        deletedContainers.append(id)
    }

    func applyItemPlan(boxID: String, plan: ItemSyncPlan) async throws(InventoryFailure) {
        if let failure { throw failure }
        itemPlans.append((boxID, plan))
    }

    func setItemTaken(
        itemID: String,
        isTaken: Bool,
        userID: String?
    ) async throws(InventoryFailure) {}

    func moveItem(itemID: String, toBoxID: String, position: Int) async throws(InventoryFailure) {}

    func uploadBoxPhoto(
        householdID: String,
        data: Data,
        fileExtension: String
    ) async throws(InventoryFailure) -> String {
        "path"
    }
}

private struct StubReader: InventoryReading {
    var allPlaces: [Box] = []
    var allRooms: [Room] = []

    func households(userID: String) async throws(InventoryFailure) -> [Household] { [] }
    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] { allRooms }
    func places(householdID: String) async throws(InventoryFailure) -> [Box] { allPlaces }
    func box(id: String) async throws(InventoryFailure) -> Box { throw InventoryFailure.notFound }
}

@MainActor
@Suite("Storage writes")
struct StorageWritesTests {

    private let rooms = [Room(id: "room-attic", name: "Attic", householdID: "hh")]

    private func place(
        _ id: String,
        name: String,
        type: String = Places.typeBox,
        parentID: String? = nil,
        items: [BoxItem] = []
    ) -> Box {
        Box(
            id: id,
            name: name,
            roomID: "room-attic",
            householdID: "hh",
            items: items,
            type: type,
            parentID: parentID
        )
    }

    private func presenter(
        _ target: StorageTarget,
        places: [Box] = [],
        writer: StubWriter
    ) async -> StoragePresenter {
        let presenter = StoragePresenter(
            target: target,
            householdID: "hh",
            repository: StubReader(allPlaces: places, allRooms: rooms),
            writes: writer
        )
        await presenter.appeared()
        return presenter
    }

    // MARK: - Making a container

    @Test("A container made at a room's level sits in the room, under nothing")
    func createAtRoomLevel() async {
        let writer = StubWriter()
        let presenter = await presenter(.room(id: "room-attic", name: "Attic"), writer: writer)

        presenter.newContainerTapped()
        presenter.containerNameChanged("  Wardrobe  ")
        presenter.containerTypeChanged("wardrobe")
        await presenter.createContainerTapped()

        #expect(writer.createdContainers == [
            .init(name: "Wardrobe", type: "wardrobe", roomID: "room-attic", parentID: nil),
        ])
        #expect(presenter.viewState.containerDraft == nil, "The sheet should close on success")
    }

    /// The room is left out on purpose: the server resolves it from the
    /// parent, and insisting would pull the new container out of the one it
    /// was just made inside.
    @Test("A container made inside another sends the parent and no room")
    func createInsideAContainer() async {
        let writer = StubWriter()
        let places = [place("wardrobe", name: "Wardrobe", type: "wardrobe")]
        let presenter = await presenter(.container(id: "wardrobe"), places: places, writer: writer)

        presenter.newContainerTapped()
        presenter.containerNameChanged("Drawer 2")
        await presenter.createContainerTapped()

        #expect(writer.createdContainers.first?.parentID == "wardrobe")
        #expect(writer.createdContainers.first?.roomID == nil)
    }

    @Test("A container with no name cannot be saved")
    func namelessContainer() async {
        let writer = StubWriter()
        let presenter = await presenter(.room(id: "room-attic", name: "Attic"), writer: writer)

        presenter.newContainerTapped()
        #expect(presenter.viewState.containerDraft?.canSave == false)

        presenter.containerNameChanged("   ")
        #expect(presenter.viewState.containerDraft?.canSave == false)
        await presenter.createContainerTapped()
        #expect(writer.createdContainers.isEmpty)

        presenter.containerNameChanged("Shelf")
        #expect(presenter.viewState.containerDraft?.canSave == true)
    }

    /// A refused write must not look like a household that would not load.
    @Test("A failed create is said in the sheet, and the list stays put")
    func failedCreate() async {
        let writer = StubWriter()
        writer.failure = .network
        let places = [place("spare", name: "Spare Box")]
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: places,
            writer: writer
        )

        presenter.newContainerTapped()
        presenter.containerNameChanged("Wardrobe")
        await presenter.createContainerTapped()

        #expect(presenter.viewState.containerDraft?.errorMessage != nil)
        #expect(presenter.viewState.containerDraft?.isSaving == false)
        guard case .contents = presenter.viewState.content else {
            Issue.record("A failed write blanked the list")
            return
        }
    }

    // MARK: - Putting something here that is not in a box

    @Test("An item added inside a container hangs off the container itself")
    func itemInAContainer() async {
        let writer = StubWriter()
        let places = [
            place("wardrobe", name: "Wardrobe", type: "wardrobe", items: [
                BoxItem(id: "coat", name: "Coat", position: 0),
            ]),
        ]
        let presenter = await presenter(.container(id: "wardrobe"), places: places, writer: writer)

        presenter.newItemTapped()
        presenter.itemNameChanged("Duvet")
        presenter.itemQuantityChanged(2)
        await presenter.addItemTapped()

        #expect(writer.createdContainers.isEmpty, "A container holds its own items")
        #expect(writer.itemPlans.first?.boxID == "wardrobe")
        #expect(writer.itemPlans.first?.plan.inserts.first?.name == "Duvet")
        #expect(writer.itemPlans.first?.plan.inserts.first?.quantity == 2)
        // After the coat, not on top of it.
        #expect(writer.itemPlans.first?.plan.inserts.first?.position == 1)
    }

    /// A room is not a place and has no id for an item to point at, so the
    /// first thing put in one makes the stand-in that holds it.
    @Test("The first item in a room makes the room's hidden holder")
    func firstItemInARoom() async {
        let writer = StubWriter()
        writer.newContainerID = "holder"
        let presenter = await presenter(.room(id: "room-attic", name: "Attic"), writer: writer)

        presenter.newItemTapped()
        presenter.itemNameChanged("Stepladder")
        await presenter.addItemTapped()

        #expect(writer.createdContainers == [
            .init(name: "", type: Places.typeRoomItems, roomID: "room-attic", parentID: nil),
        ])
        #expect(writer.itemPlans.first?.boxID == "holder")
    }

    @Test("A room that already has a holder does not get a second one")
    func secondItemInARoom() async {
        let writer = StubWriter()
        let places = [place("holder", name: "", type: Places.typeRoomItems)]
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: places,
            writer: writer
        )

        presenter.newItemTapped()
        presenter.itemNameChanged("Bike")
        await presenter.addItemTapped()

        #expect(writer.createdContainers.isEmpty)
        #expect(writer.itemPlans.first?.boxID == "holder")
    }

    @Test("Quantity cannot go below one")
    func quantityFloor() async {
        let writer = StubWriter()
        let presenter = await presenter(.room(id: "room-attic", name: "Attic"), writer: writer)

        presenter.newItemTapped()
        presenter.itemQuantityChanged(0)
        #expect(presenter.viewState.itemDraft?.quantity == 1)
    }

    // MARK: - Removing a container

    @Test("Deleting says what happens to the contents, and only then deletes")
    func deleteAsks() async {
        let writer = StubWriter()
        let places = [
            place("wardrobe", name: "Wardrobe", type: "wardrobe"),
            place("winter", name: "Winter Clothes", parentID: "wardrobe"),
        ]
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: places,
            writer: writer
        )

        presenter.deleteTapped(id: "wardrobe")
        let prompt = presenter.viewState.deletePrompt
        #expect(prompt?.id == "wardrobe")
        #expect(prompt?.message.contains("moves out one level") == true)
        #expect(writer.deletedContainers.isEmpty, "Nothing goes before the answer")

        await presenter.confirmDeleteTapped()
        #expect(writer.deletedContainers == ["wardrobe"])
        #expect(presenter.viewState.deletePrompt == nil)
    }

    @Test("An empty container says nothing moves")
    func deleteEmpty() async {
        let writer = StubWriter()
        let places = [place("wardrobe", name: "Wardrobe", type: "wardrobe")]
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: places,
            writer: writer
        )

        presenter.deleteTapped(id: "wardrobe")
        #expect(presenter.viewState.deletePrompt?.message.contains("nothing moves") == true)
    }

    @Test("Backing out of the question deletes nothing")
    func deleteCancelled() async {
        let writer = StubWriter()
        let places = [place("wardrobe", name: "Wardrobe", type: "wardrobe")]
        let presenter = await presenter(
            .room(id: "room-attic", name: "Attic"),
            places: places,
            writer: writer
        )

        presenter.deleteTapped(id: "wardrobe")
        presenter.dismissDelete()
        await presenter.confirmDeleteTapped()

        #expect(writer.deletedContainers.isEmpty)
    }
}
