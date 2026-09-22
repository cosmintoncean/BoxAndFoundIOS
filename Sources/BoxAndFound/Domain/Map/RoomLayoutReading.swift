import Foundation

/// The saved maps, stated without naming Supabase.
protocol RoomLayoutReading: Sendable {
    /// The layout for a room, or nil when the room has never been mapped.
    ///
    /// One row per room, and a room with no row is the normal case — most
    /// rooms are never drawn — so absence is an answer rather than a failure.
    func layout(roomID: String) async throws(InventoryFailure) -> RoomLayout?
}
