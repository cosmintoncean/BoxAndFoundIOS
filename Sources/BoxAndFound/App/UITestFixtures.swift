#if DEBUG
import Foundation

/// Runs the real screens against in-memory data when a UI test launches the
/// app.
///
/// This exists because of a constraint rather than a preference: the project
/// is written on Windows, so until someone opens it on a device the only thing
/// that can exercise a view tree is a simulator under CI. A unit test can
/// check that a presenter produces the right view state; only this can catch a
/// navigation destination that never fires, a button disabled when it should
/// not be, or a form that will not render at all.
///
/// `#if DEBUG` keeps every byte of it out of a release build.
enum UITestFixtures {

    static let launchArgument = "-uiTestFixtures"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static let userID = "fixture-user"

    /// Swaps the repositories and hands back a session that is already signed
    /// in, so the test starts on the inventory rather than the sign-in form.
    ///
    /// Main-actor isolated because everything it touches is: the composition
    /// root and the session store both belong to the actor the UI runs on, and
    /// its only caller is `RootPresenter.forLaunch()`.
    @MainActor
    static func install() -> SessionStore {
        let inventory = FixtureInventory()
        let notifications = FixtureNotifications()
        Dependencies.use(
            Dependencies.Overrides(
                inventoryReading: inventory,
                inventoryWriting: inventory,
                households: inventory,
                notifications: notifications,
                nudges: notifications
            )
        )
        return SessionStore(
            fixed: .signedIn(
                SignedInUser(id: userID, email: "tester@boxandfound.net", isPremium: false)
            )
        )
    }
}

/// One household's inventory, in memory, with writes visible to the next read.
///
/// Writes have to land for the tests to be worth anything: taking an item has
/// to change what the list says about it afterwards, which is exactly the kind
/// of round trip a presenter unit test cannot check.
///
/// `@unchecked Sendable` because `InventoryReading` and `InventoryWriting` are
/// `Sendable` and this holds plain mutable state. Every caller is a main-actor
/// presenter, so the state is only ever touched from one actor.
final class FixtureInventory: InventoryReading, InventoryWriting, HouseholdManaging, @unchecked Sendable {

    static let householdID = "fixture-household"

    private var households: [Household] = [
        Household(id: FixtureInventory.householdID, name: "Home", inviteCode: "ABC123", ownerID: UITestFixtures.userID),
    ]

    private var rooms: [Room] = [
        Room(id: "room-garage", name: "Garage", householdID: FixtureInventory.householdID),
        Room(id: "room-attic", name: "Attic", householdID: FixtureInventory.householdID),
    ]

    private var boxes: [Box] = [
        Box(
            id: "box-winter",
            name: "Winter Clothes",
            location: "Top shelf",
            icon: "suitcase",
            roomID: "room-attic",
            householdID: FixtureInventory.householdID,
            items: [
                BoxItem(id: "item-scarf", name: "Scarf", quantity: 1, position: 0),
                BoxItem(id: "item-gloves", name: "Gloves", quantity: 2, position: 1),
            ]
        ),
        Box(
            id: "box-tools",
            name: "Tools",
            location: "Bench",
            icon: "box",
            roomID: "room-garage",
            householdID: FixtureInventory.householdID,
            items: [BoxItem(id: "item-hammer", name: "Hammer", quantity: 1, position: 0)]
        ),
        Box(
            id: "box-spare",
            name: "Spare Box",
            icon: "cardbox",
            householdID: FixtureInventory.householdID
        ),
    ]

    private var nextID = 0

    private func makeID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)-\(nextID)"
    }

    // MARK: - Reading

    func households(userID: String) async throws(InventoryFailure) -> [Household] { households }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        rooms.filter { $0.householdID == householdID }
    }

    func boxes(householdID: String) async throws(InventoryFailure) -> [Box] {
        boxes.filter { $0.householdID == householdID }
    }

    func box(id: String) async throws(InventoryFailure) -> Box {
        guard let box = boxes.first(where: { $0.id == id }) else { throw InventoryFailure.notFound }
        return box
    }

    // MARK: - Writing

    func createRoom(householdID: String, name: String) async throws(InventoryFailure) -> Room {
        let room = Room(id: makeID("room"), name: name, householdID: FixtureInventory.householdID)
        rooms.append(room)
        return room
    }

    func deleteRoom(id: String) async throws(InventoryFailure) {
        rooms.removeAll { $0.id == id }
    }

    func createBox(
        householdID: String,
        name: String,
        icon: String,
        location: String?,
        roomID: String?,
        imageURL: String?
    ) async throws(InventoryFailure) -> Box {
        let box = Box(
            id: makeID("box"),
            name: name,
            imageURL: imageURL,
            location: location,
            icon: icon,
            roomID: roomID,
            householdID: FixtureInventory.householdID
        )
        boxes.append(box)
        return box
    }

    func updateBox(id: String, changes: BoxChanges) async throws(InventoryFailure) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        let old = boxes[index]
        boxes[index] = Box(
            id: old.id,
            name: value(changes.name, old.name),
            imageURL: value(changes.imageURL, old.imageURL),
            location: value(changes.location, old.location),
            icon: value(changes.icon, old.icon),
            roomID: value(changes.roomID, old.roomID),
            householdID: old.householdID,
            items: old.items
        )
    }

    func deleteBox(id: String) async throws(InventoryFailure) {
        boxes.removeAll { $0.id == id }
    }

    func applyItemPlan(boxID: String, plan: ItemSyncPlan) async throws(InventoryFailure) {
        guard let index = boxes.firstIndex(where: { $0.id == boxID }) else { return }
        var items = boxes[index].items

        for update in plan.updates {
            guard let itemIndex = items.firstIndex(where: { $0.id == update.id }) else { continue }
            let old = items[itemIndex]
            // Read once: taken, taken_at and taken_by move together or not at
            // all, and `map` over an optional-typed member would nest.
            let taken = update.taken
            items[itemIndex] = BoxItem(
                id: old.id,
                name: update.name ?? old.name,
                quantity: update.quantity ?? old.quantity,
                position: update.position ?? old.position,
                isTaken: taken?.isTaken ?? old.isTaken,
                takenAt: taken == nil ? old.takenAt : taken?.at,
                takenBy: taken == nil ? old.takenBy : taken?.by
            )
        }

        for insert in plan.inserts {
            items.append(
                BoxItem(
                    id: makeID("item"),
                    name: insert.name,
                    quantity: insert.quantity,
                    position: insert.position,
                    isTaken: insert.isTaken,
                    takenAt: insert.takenAt,
                    takenBy: insert.takenBy
                )
            )
        }

        items.removeAll { plan.deletes.contains($0.id) }
        boxes[index] = rebuilt(boxes[index], items: items)
    }

    func setItemTaken(
        itemID: String,
        isTaken: Bool,
        userID: String?
    ) async throws(InventoryFailure) {
        for (boxIndex, box) in boxes.enumerated() {
            guard let itemIndex = box.items.firstIndex(where: { $0.id == itemID }) else { continue }
            var items = box.items
            let old = items[itemIndex]
            items[itemIndex] = BoxItem(
                id: old.id,
                name: old.name,
                quantity: old.quantity,
                position: old.position,
                isTaken: isTaken,
                takenAt: isTaken ? ItemSync.timestamp() : nil,
                takenBy: isTaken ? userID : nil
            )
            boxes[boxIndex] = rebuilt(box, items: items)
            return
        }
    }

    func moveItem(itemID: String, toBoxID: String, position: Int) async throws(InventoryFailure) {
        guard
            let fromIndex = boxes.firstIndex(where: { $0.items.contains { $0.id == itemID } }),
            let toIndex = boxes.firstIndex(where: { $0.id == toBoxID }),
            let item = boxes[fromIndex].items.first(where: { $0.id == itemID })
        else { return }

        var source = boxes[fromIndex].items
        source.removeAll { $0.id == itemID }
        boxes[fromIndex] = rebuilt(boxes[fromIndex], items: source)

        var destination = boxes[toIndex].items
        destination.append(
            BoxItem(
                id: item.id,
                name: item.name,
                quantity: item.quantity,
                position: position,
                isTaken: item.isTaken,
                takenAt: item.takenAt,
                takenBy: item.takenBy
            )
        )
        boxes[toIndex] = rebuilt(boxes[toIndex], items: destination)
    }

    func uploadBoxPhoto(
        householdID: String,
        data: Data,
        fileExtension: String
    ) async throws(InventoryFailure) -> String {
        "\(householdID)/fixture.\(fileExtension)"
    }

    // MARK: - Households

    func create(name: String, ownerID: String) async throws(HouseholdFailure) -> Household {
        let household = Household(
            id: makeID("household"),
            name: name,
            inviteCode: InviteCode.random(),
            ownerID: ownerID
        )
        households.append(household)
        return household
    }

    func rename(householdID: String, name: String) async throws(HouseholdFailure) {
        guard let index = households.firstIndex(where: { $0.id == householdID }) else { return }
        let old = households[index]
        households[index] = Household(
            id: old.id, name: name, inviteCode: old.inviteCode, ownerID: old.ownerID
        )
    }

    func regenerateInviteCode(householdID: String) async throws(HouseholdFailure) -> String {
        let code = InviteCode.random()
        guard let index = households.firstIndex(where: { $0.id == householdID }) else { return code }
        let old = households[index]
        households[index] = Household(
            id: old.id, name: old.name, inviteCode: code, ownerID: old.ownerID
        )
        return code
    }

    func previewInvite(code: String) async throws(HouseholdFailure) -> InvitePreview {
        let wanted = InviteCode.normalise(code)
        guard let match = households.first(where: { $0.inviteCode == wanted }) else {
            throw HouseholdFailure.unknownInviteCode
        }
        return InvitePreview(
            householdID: match.id,
            householdName: match.name,
            ownerName: "Fixture Owner",
            memberCount: 2,
            isAlreadyMember: match.ownerID == UITestFixtures.userID
        )
    }

    func join(householdID: String, userID: String) async throws(HouseholdFailure) {}

    func leave(householdID: String, userID: String) async throws(HouseholdFailure) {
        households.removeAll { $0.id == householdID }
    }

    func members(householdID: String) async throws(HouseholdFailure) -> [HouseholdMember] {
        [HouseholdMember(userID: UITestFixtures.userID, displayName: "Tester", email: nil)]
    }

    func delete(householdID: String) async throws(HouseholdFailure) {
        households.removeAll { $0.id == householdID }
        rooms.removeAll { $0.householdID == householdID }
        boxes.removeAll { $0.householdID == householdID }
    }

    // MARK: -

    private func value<T: Equatable & Sendable>(_ change: FieldChange<T>, _ current: T?) -> T? {
        guard case .set(let new) = change else { return current }
        return new
    }

    /// `Box` sorts its items in `init`, so rebuilding is how an edited box
    /// comes back out in display order — the same thing the real repository
    /// gets for free by decoding a fresh row.
    private func rebuilt(_ box: Box, items: [BoxItem]) -> Box {
        Box(
            id: box.id,
            name: box.name,
            imageURL: box.imageURL,
            location: box.location,
            icon: box.icon,
            roomID: box.roomID,
            householdID: box.householdID,
            items: items
        )
    }
}
#endif
