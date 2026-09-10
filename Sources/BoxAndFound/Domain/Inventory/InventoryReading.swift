import Foundation

/// What a presenter needs from the inventory, stated without naming Supabase.
///
/// The protocol lives in the domain and the implementation in the data layer,
/// which is what lets a presenter test run the real grouping, search and
/// empty-state logic against fixed data — the payoff MVP is supposed to buy.
protocol InventoryReading: Sendable {
    func households(userID: String) async throws(InventoryFailure) -> [Household]
    func rooms(householdID: String) async throws(InventoryFailure) -> [Room]
    func boxes(householdID: String) async throws(InventoryFailure) -> [Box]
    func box(id: String) async throws(InventoryFailure) -> Box
}
