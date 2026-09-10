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
