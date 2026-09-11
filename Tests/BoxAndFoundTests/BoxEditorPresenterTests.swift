import Foundation
import Testing
@testable import BoxAndFound

/// Records what was written rather than writing it.
///
/// `@unchecked Sendable` because `InventoryWriting` is `Sendable` and this
/// holds plain mutable state. Justified here and nowhere else: every test that
/// touches it is `@MainActor`, so the recorded calls are only ever read from
/// the same actor that made them.
private final class StubWriter: InventoryWriting, @unchecked Sendable {
    var createdBoxes: [(name: String, icon: String, location: String?, roomID: String?, imageURL: String?)] = []
    var boxChanges: [(id: String, changes: BoxChanges)] = []
    var itemPlans: [(boxID: String, plan: ItemSyncPlan)] = []
    var takenCalls: [(itemID: String, isTaken: Bool, userID: String?)] = []
    var deletedBoxes: [String] = []
    var uploads: [(householdID: String, fileExtension: String, byteCount: Int)] = []
    var failure: InventoryFailure?

    /// Handed back by `createBox`, so a test can see what the plan was applied to.
    var newBoxID = "new-box"

    func createRoom(householdID: String, name: String) async throws(InventoryFailure) -> Room {
        if let failure { throw failure }
        return Room(id: "room", name: name, householdID: householdID)
    }

    func deleteRoom(id: String) async throws(InventoryFailure) {
        if let failure { throw failure }
    }

    func createBox(
        householdID: String,
        name: String,
        icon: String,
        location: String?,
        roomID: String?,
        imageURL: String?
    ) async throws(InventoryFailure) -> Box {
        if let failure { throw failure }
        createdBoxes.append((name, icon, location, roomID, imageURL))
        return Box(
            id: newBoxID,
            name: name,
            imageURL: imageURL,
            location: location,
            icon: icon,
            roomID: roomID,
            householdID: householdID
        )
    }

    func updateBox(id: String, changes: BoxChanges) async throws(InventoryFailure) {
        if let failure { throw failure }
        boxChanges.append((id, changes))
    }

    func deleteBox(id: String) async throws(InventoryFailure) {
        if let failure { throw failure }
        deletedBoxes.append(id)
    }

    func applyItemPlan(boxID: String, plan: ItemSyncPlan) async throws(InventoryFailure) {
        if let failure { throw failure }
        itemPlans.append((boxID, plan))
    }

    func setItemTaken(itemID: String, isTaken: Bool, userID: String?) async throws(InventoryFailure) {
        if let failure { throw failure }
        takenCalls.append((itemID, isTaken, userID))
    }

    func moveItem(itemID: String, toBoxID: String, position: Int) async throws(InventoryFailure) {}

    func uploadBoxPhoto(
        householdID: String,
        data: Data,
        fileExtension: String
    ) async throws(InventoryFailure) -> String {
        if let failure { throw failure }
        uploads.append((householdID, fileExtension, data.count))
        return "\(householdID)/uploaded.\(fileExtension)"
    }
}

private struct StubReader: InventoryReading {
    var rooms: [Room] = []
    var box: Box?
    var failure: InventoryFailure?

    func households(userID: String) async throws(InventoryFailure) -> [Household] { [] }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        if let failure { throw failure }
        return rooms
    }

    func boxes(householdID: String) async throws(InventoryFailure) -> [Box] { [] }

    func box(id: String) async throws(InventoryFailure) -> Box {
        if let failure { throw failure }
        guard let box else { throw InventoryFailure.notFound }
        return box
    }
}


/// Records nudges instead of sending them.
///
/// Passed explicitly everywhere a BoxDetailPresenter is built in these tests:
/// the default would be the real repository, and a unit test that quietly
/// opens a socket is a slow test that fails on a train.
private final class StubNudges: NudgeManaging, @unchecked Sendable {
    var availabilityToReturn: NudgeAvailability = .available
    var pendingToReturn: [Nudge] = []
    var sent: [(itemID: String, recipientID: String, itemName: String, message: String?)] = []
    var failure: NotificationFailure?

    func availability(
        itemID: String,
        now: Date
    ) async throws(NotificationFailure) -> NudgeAvailability {
        if let failure { throw failure }
        return availabilityToReturn
    }

    func send(
        itemID: String,
        boxID: String,
        householdID: String,
        senderID: String,
        recipientID: String,
        itemName: String,
        boxName: String?,
        message: String?
    ) async throws(NotificationFailure) {
        if let failure { throw failure }
        sent.append((itemID, recipientID, itemName, message))
    }

    func pending(
        recipientID: String,
        householdID: String
    ) async throws(NotificationFailure) -> [Nudge] {
        if let failure { throw failure }
        return pendingToReturn
    }

    func dismiss(nudgeID: String) async throws(NotificationFailure) {}
}

@Suite("Box editor")
@MainActor
struct BoxEditorPresenterTests {

    private func editor(
        boxID: String? = nil,
        reader: StubReader = StubReader(),
        writer: StubWriter = StubWriter()
    ) -> BoxEditorPresenter {
        BoxEditorPresenter(
            householdID: "h1",
            boxID: boxID,
            userID: "user-1",
            reader: reader,
            writer: writer
        )
    }

    // MARK: - Creating

    @Test("A new box opens on an empty form, not a spinner")
    func newBoxOpensEmpty() {
        let state = editor().viewState
        #expect(state.title == "New box")
        #expect(!state.isLoading)
        #expect(state.saveTitle == "Create box")
        #expect(!state.isDeleteVisible)
        #expect(state.items.isEmpty)
    }

    @Test("Saving is refused until the box has a name")
    func nameIsRequired() {
        let presenter = editor()
        #expect(!presenter.viewState.isSaveEnabled)

        presenter.nameChanged("   ")
        #expect(!presenter.viewState.isSaveEnabled)

        presenter.nameChanged("Winter")
        #expect(presenter.viewState.isSaveEnabled)
    }

    @Test("All twelve icons are offered, with the default already chosen")
    func iconsAreOffered() {
        let icons = editor().viewState.icons
        #expect(icons.map(\.key) == BoxIcons.keys)
        #expect(icons.filter(\.isSelected).map(\.key) == [BoxIcons.defaultKey])
    }

    @Test("No room is an option, and the first one")
    func noRoomIsOffered() async {
        let reader = StubReader(rooms: [Room(id: "r1", name: "Garage", householdID: "h1")])
        let presenter = editor(reader: reader)
        await presenter.appeared()

        let rooms = presenter.viewState.rooms
        #expect(rooms.map(\.name) == [InventoryCopy.unassignedRoom, "Garage"])
        #expect(rooms[0].isSelected)
    }

    @Test("Creating writes the box, then its items")
    func creatingWritesBoxThenItems() async {
        let writer = StubWriter()
        let presenter = editor(writer: writer)

        presenter.nameChanged("Winter")
        presenter.locationChanged(" Attic ")
        presenter.iconSelected("suitcase")
        presenter.newItemNameChanged("Scarf")
        presenter.addItemTapped()
        await presenter.saveTapped()

        #expect(writer.createdBoxes.count == 1)
        #expect(writer.createdBoxes[0].name == "Winter")
        #expect(writer.createdBoxes[0].icon == "suitcase")
        #expect(writer.createdBoxes[0].location == "Attic")

        #expect(writer.itemPlans.count == 1)
        #expect(writer.itemPlans[0].boxID == "new-box")
        #expect(writer.itemPlans[0].plan.inserts.map(\.name) == ["Scarf"])
        #expect(presenter.viewState.isFinished)
    }

    @Test("An icon another client invented is normalised before it is written")
    func iconIsNormalised() async {
        let writer = StubWriter()
        let presenter = editor(writer: writer)
        presenter.nameChanged("Winter")
        presenter.iconSelected("crate")
        await presenter.saveTapped()

        #expect(writer.createdBoxes[0].icon == BoxIcons.defaultKey)
    }

    // MARK: - Items

    @Test("Adding an item trims it and clears the field")
    func addingAnItem() {
        let presenter = editor()
        presenter.newItemNameChanged("  Scarf  ")
        presenter.addItemTapped()

        #expect(presenter.viewState.items.map(\.name) == ["Scarf"])
        #expect(presenter.viewState.newItemName.isEmpty)
    }

    @Test("A blank item is not added at all")
    func blankItemsAreRefused() {
        let presenter = editor()
        presenter.newItemNameChanged("   ")
        presenter.addItemTapped()
        #expect(presenter.viewState.items.isEmpty)
    }

    @Test("Quantity never drops below one")
    func quantityFloor() {
        let presenter = editor()
        presenter.newItemNameChanged("Scarf")
        presenter.addItemTapped()
        let id = presenter.viewState.items[0].id

        presenter.itemQuantityChanged(id, by: -5)
        #expect(presenter.viewState.items[0].quantity == 1)

        presenter.itemQuantityChanged(id, by: 2)
        #expect(presenter.viewState.items[0].quantity == 3)
        #expect(presenter.viewState.items[0].quantityLabel == "×3")
    }

    @Test("A single item shows no quantity label")
    func singleQuantityIsUnlabelled() {
        let presenter = editor()
        presenter.newItemNameChanged("Scarf")
        presenter.addItemTapped()
        #expect(presenter.viewState.items[0].quantityLabel == nil)
    }

    // MARK: - Editing

    private func loadedEditor(
        _ box: Box,
        writer: StubWriter = StubWriter()
    ) async -> BoxEditorPresenter {
        let presenter = editor(boxID: box.id, reader: StubReader(box: box), writer: writer)
        await presenter.appeared()
        return presenter
    }

    @Test("Editing fills the form from the box that is there")
    func editingLoadsTheBox() async {
        let box = Box(
            id: "b1", name: "Winter", location: "Attic", icon: "suitcase", roomID: "r1",
            items: [BoxItem(id: "i1", name: "Scarf", quantity: 2)]
        )
        let state = await loadedEditor(box).viewState

        #expect(state.title == "Edit box")
        #expect(state.name == "Winter")
        #expect(state.location == "Attic")
        #expect(state.icons.filter(\.isSelected).map(\.key) == ["suitcase"])
        #expect(state.items.map(\.name) == ["Scarf"])
        #expect(state.isDeleteVisible)
        #expect(state.saveTitle == "Save changes")
    }

    /// The whole point of `BoxChanges`: saving must not overwrite a field
    /// another member edited while this editor was open.
    @Test("Saving an untouched box writes no box fields at all")
    func untouchedBoxWritesNothing() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", location: "Attic", icon: "suitcase")
        let presenter = await loadedEditor(box, writer: writer)

        await presenter.saveTapped()

        #expect(writer.boxChanges.count == 1)
        #expect(writer.boxChanges[0].changes.isEmpty)
    }

    @Test("Only the field that moved is sent")
    func onlyChangedFieldsAreSent() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", location: "Attic", icon: "suitcase")
        let presenter = await loadedEditor(box, writer: writer)

        presenter.nameChanged("Winter clothes")
        await presenter.saveTapped()

        let changes = writer.boxChanges[0].changes
        #expect(changes.name == .set("Winter clothes"))
        #expect(changes.location == .unchanged)
        #expect(changes.icon == .unchanged)
        #expect(changes.roomID == .unchanged)
    }

    @Test("Clearing the location clears the column rather than writing an empty string")
    func clearingLocationSetsNull() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", location: "Attic")
        let presenter = await loadedEditor(box, writer: writer)

        presenter.locationChanged("")
        await presenter.saveTapped()

        #expect(writer.boxChanges[0].changes.location == .set(nil))
    }

    @Test("An untouched item list produces an empty plan")
    func untouchedItemsProduceNoPlan() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", items: [BoxItem(id: "i1", name: "Scarf")])
        let presenter = await loadedEditor(box, writer: writer)

        await presenter.saveTapped()

        #expect(writer.itemPlans[0].plan.isEmpty)
    }

    @Test("Removing an item plans a delete, keeping its id out of the inserts")
    func removingAnItemPlansADelete() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", items: [
            BoxItem(id: "i1", name: "Scarf", position: 0),
            BoxItem(id: "i2", name: "Gloves", position: 1),
        ])
        let presenter = await loadedEditor(box, writer: writer)

        presenter.itemRemoved(presenter.viewState.items[0].id)
        await presenter.saveTapped()

        let plan = writer.itemPlans[0].plan
        #expect(plan.deletes == ["i1"])
        #expect(plan.inserts.isEmpty)
        #expect(plan.updates.map(\.id) == ["i2"])
        #expect(plan.updates[0].position == 0)
    }

    // MARK: - Photos

    @Test("A picked photo is uploaded first, and its path is what the box stores")
    func photoIsUploadedBeforeTheBox() async {
        let writer = StubWriter()
        let presenter = editor(writer: writer)

        presenter.nameChanged("Winter")
        presenter.photoPicked(data: Data([1, 2, 3]), fileExtension: "heic")
        #expect(presenter.viewState.photo == .picked)

        await presenter.saveTapped()

        #expect(writer.uploads.count == 1)
        #expect(writer.uploads[0].fileExtension == "heic")
        #expect(writer.uploads[0].householdID == "h1")
        #expect(writer.createdBoxes[0].imageURL == "h1/uploaded.heic")
    }

    @Test("Removing an existing photo clears the column")
    func removingAPhotoClearsTheColumn() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", imageURL: "h1/old.jpg")
        let presenter = await loadedEditor(box, writer: writer)

        presenter.photoRemoved()
        #expect(presenter.viewState.photo == .none)

        await presenter.saveTapped()
        #expect(writer.boxChanges[0].changes.imageURL == .set(nil))
    }

    @Test("A box that never had a photo does not write one away")
    func noPhotoMeansNoChange() async {
        let writer = StubWriter()
        let presenter = await loadedEditor(Box(id: "b1", name: "Winter"), writer: writer)

        presenter.photoRemoved()
        await presenter.saveTapped()

        #expect(writer.boxChanges[0].changes.imageURL == .unchanged)
    }

    // MARK: - Deleting and failing

    @Test("Deleting removes the box and closes the screen")
    func deleting() async {
        let writer = StubWriter()
        let presenter = await loadedEditor(Box(id: "b1", name: "Winter"), writer: writer)

        await presenter.deleteTapped()

        #expect(writer.deletedBoxes == ["b1"])
        #expect(presenter.viewState.isFinished)
    }

    @Test("A failed save says so and keeps the screen open with the work on it")
    func failedSaveKeepsTheScreen() async {
        let writer = StubWriter()
        writer.failure = .network
        let presenter = editor(writer: writer)

        presenter.nameChanged("Winter")
        await presenter.saveTapped()

        #expect(!presenter.viewState.isFinished)
        #expect(presenter.viewState.notice?.kind == .error)
        #expect(presenter.viewState.name == "Winter")
    }
}

@Suite("Taking and returning")
@MainActor
struct BoxDetailWriteTests {

    @Test("Tapping an item takes it, stamped with who did it")
    func tappingTakes() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", items: [BoxItem(id: "i1", name: "Scarf")])
        let presenter = BoxDetailPresenter(
            boxID: "b1",
            title: "Winter",
            householdID: "h1",
            userID: "user-1",
            reader: StubReader(box: box),
            writer: writer,
            nudges: StubNudges()
        )
        await presenter.appeared()
        await presenter.itemTapped("i1")

        #expect(writer.takenCalls.count == 1)
        #expect(writer.takenCalls[0].itemID == "i1")
        #expect(writer.takenCalls[0].isTaken)
        #expect(writer.takenCalls[0].userID == "user-1")
    }

    @Test("Tapping a taken item puts it back")
    func tappingReturns() async {
        let writer = StubWriter()
        let box = Box(id: "b1", name: "Winter", items: [
            BoxItem(id: "i1", name: "Scarf", isTaken: true),
        ])
        let presenter = BoxDetailPresenter(
            boxID: "b1",
            title: "Winter",
            householdID: "h1",
            userID: "user-1",
            reader: StubReader(box: box),
            writer: writer,
            nudges: StubNudges()
        )
        await presenter.appeared()
        await presenter.itemTapped("i1")

        #expect(writer.takenCalls[0].isTaken == false)
    }

    @Test("An item that is not in the box is not written")
    func unknownItemIsIgnored() async {
        let writer = StubWriter()
        let presenter = BoxDetailPresenter(
            boxID: "b1",
            title: "Winter",
            householdID: "h1",
            userID: "user-1",
            reader: StubReader(box: Box(id: "b1", name: "Winter")),
            writer: writer,
            nudges: StubNudges()
        )
        await presenter.appeared()
        await presenter.itemTapped("not-here")

        #expect(writer.takenCalls.isEmpty)
    }
}

@Suite("Asking for an item back")
@MainActor
struct NudgeFromBoxDetailTests {

    private func box(takenBy: String?) -> Box {
        Box(id: "b1", name: "Winter", items: [
            BoxItem(id: "i1", name: "Scarf", isTaken: takenBy != nil, takenBy: takenBy),
        ])
    }

    private func makePresenter(
        _ box: Box,
        nudges: StubNudges = StubNudges()
    ) -> BoxDetailPresenter {
        BoxDetailPresenter(
            boxID: "b1",
            title: "Winter",
            householdID: "h1",
            userID: "user-1",
            reader: StubReader(box: box),
            writer: StubWriter(),
            nudges: nudges
        )
    }

    private func rows(_ presenter: BoxDetailPresenter) -> [BoxDetailViewState.ItemRow] {
        guard case .loaded(let loaded) = presenter.viewState.content else { return [] }
        return loaded.items
    }

    @Test("Asking is offered for an item someone else took")
    func offeredForSomeoneElse() async {
        let presenter = makePresenter(box(takenBy: "someone-else"))
        await presenter.appeared()
        #expect(rows(presenter).first?.canAskBack == true)
    }

    /// Asking yourself for something back is not a feature.
    @Test("Asking is not offered for an item you took yourself")
    func notOfferedForYourOwn() async {
        let presenter = makePresenter(box(takenBy: "user-1"))
        await presenter.appeared()
        #expect(rows(presenter).first?.canAskBack == false)
    }

    @Test("Asking is not offered for an item nobody has taken")
    func notOfferedWhenPresent() async {
        let presenter = makePresenter(box(takenBy: nil))
        await presenter.appeared()
        #expect(rows(presenter).first?.canAskBack == false)
    }

    @Test("Sending carries the recipient and a snapshot of the name")
    func sending() async {
        let nudges = StubNudges()
        let presenter = makePresenter(box(takenBy: "someone-else"), nudges: nudges)
        await presenter.appeared()

        await presenter.askBackTapped("i1")
        presenter.nudgeMessageChanged("Need it tonight")
        await presenter.sendNudgeTapped()

        #expect(nudges.sent.count == 1)
        #expect(nudges.sent[0].recipientID == "someone-else")
        #expect(nudges.sent[0].itemName == "Scarf")
        #expect(nudges.sent[0].message == "Need it tonight")
        // The sheet closes and says so.
        #expect(presenter.viewState.nudgeSheet == nil)
        #expect(presenter.viewState.notice == NotificationCopy.nudgeSent)
    }

    @Test("Inside the window the sheet explains itself and refuses to send")
    func cooldownBlocks() async {
        let nudges = StubNudges()
        nudges.availabilityToReturn = .onCooldown(remaining: 3 * 3600)
        let presenter = makePresenter(box(takenBy: "someone-else"), nudges: nudges)
        await presenter.appeared()

        await presenter.askBackTapped("i1")

        let sheet = presenter.viewState.nudgeSheet
        #expect(sheet?.canSend == false)
        #expect(sheet?.cooldownNote?.contains("3 hours") == true)

        await presenter.sendNudgeTapped()
        #expect(nudges.sent.isEmpty)
    }

    /// The server enforces the window regardless, so refusing on a failed
    /// lookup would be stricter than the rule itself.
    @Test("A cooldown that cannot be read does not block the ask")
    func unreadableCooldownAllows() async {
        let nudges = StubNudges()
        nudges.failure = .network
        let presenter = makePresenter(box(takenBy: "someone-else"), nudges: nudges)
        await presenter.appeared()

        await presenter.askBackTapped("i1")
        #expect(presenter.viewState.nudgeSheet?.canSend == true)
    }

    @Test("Requests pointed at you show on the box they are about")
    func pendingNotesAppear() async {
        let nudges = StubNudges()
        nudges.pendingToReturn = [
            Nudge(
                id: "n1", itemID: "i1", boxID: "b1", senderID: "someone-else",
                itemName: "Scarf", boxName: "Winter", message: "Please",
                createdAt: "2026-09-11T12:00:00Z"
            ),
            // A different box: not this screen's business.
            Nudge(
                id: "n2", itemID: "i9", boxID: "b9", senderID: "someone-else",
                itemName: "Hammer", boxName: "Tools", message: nil,
                createdAt: "2026-09-11T12:00:00Z"
            ),
        ]
        let presenter = makePresenter(box(takenBy: "user-1"), nudges: nudges)
        await presenter.appeared()

        guard case .loaded(let loaded) = presenter.viewState.content else {
            Issue.record("Expected a loaded box")
            return
        }
        #expect(loaded.pendingNotes.count == 1)
        #expect(loaded.pendingNotes[0].contains("Scarf"))
        #expect(loaded.pendingNotes[0].contains("Please"))
    }
}
