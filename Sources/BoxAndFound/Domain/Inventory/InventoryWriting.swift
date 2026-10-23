import Foundation

/// Every write the inventory makes, stated without naming Supabase.
///
/// Split from `InventoryReading` rather than bolted onto it: a screen that
/// only lists boxes has no business being handed a delete, and the split keeps
/// the one genuinely delicate operation — the item diff — next to nothing
/// else.
protocol InventoryWriting: Sendable {

    // Rooms
    func createRoom(householdID: String, name: String) async throws(InventoryFailure) -> Room
    func deleteRoom(id: String) async throws(InventoryFailure)

    // Boxes
    func createBox(
        householdID: String,
        name: String,
        icon: String,
        location: String?,
        roomID: String?,
        imageURL: String?
    ) async throws(InventoryFailure) -> Box
    func updateBox(id: String, changes: BoxChanges) async throws(InventoryFailure)
    func deleteBox(id: String) async throws(InventoryFailure)

    // Containers
    //
    // A container is a row in the same table as a box, which is why these take
    // and return the same type. What separates the two is `type` — the one
    // column the compatibility view does not expose, and so the reason these
    // cannot go through it.
    func createContainer(
        householdID: String,
        name: String,
        type: String,
        roomID: String?,
        parentID: String?
    ) async throws(InventoryFailure) -> Box
    /// Puts a place inside another, or back into a room with a nil `parentID`.
    func movePlace(
        id: String,
        parentID: String?,
        roomID: String?
    ) async throws(InventoryFailure)
    /// Leaves whatever was inside it one level up rather than taking it along.
    func deleteContainer(id: String) async throws(InventoryFailure)

    // Items
    func applyItemPlan(boxID: String, plan: ItemSyncPlan) async throws(InventoryFailure)
    func setItemTaken(
        itemID: String,
        isTaken: Bool,
        userID: String?
    ) async throws(InventoryFailure)
    func moveItem(itemID: String, toBoxID: String, position: Int) async throws(InventoryFailure)

    // Photos
    func uploadBoxPhoto(
        householdID: String,
        data: Data,
        fileExtension: String
    ) async throws(InventoryFailure) -> String
}
