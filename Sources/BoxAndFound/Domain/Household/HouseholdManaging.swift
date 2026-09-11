import Foundation

/// Everything a household screen needs, stated without naming Supabase.
protocol HouseholdManaging: Sendable {
    func create(name: String, ownerID: String) async throws(HouseholdFailure) -> Household
    func rename(householdID: String, name: String) async throws(HouseholdFailure)

    /// Rotating the code invalidates every invite link already shared.
    func regenerateInviteCode(householdID: String) async throws(HouseholdFailure) -> String

    /// Look up an invite without accepting it, so a person sees what they are
    /// joining before they join it.
    func previewInvite(code: String) async throws(HouseholdFailure) -> InvitePreview

    func join(householdID: String, userID: String) async throws(HouseholdFailure)

    /// Removes only your own membership row. Owners cannot leave; they delete.
    func leave(householdID: String, userID: String) async throws(HouseholdFailure)

    func members(householdID: String) async throws(HouseholdFailure) -> [HouseholdMember]

    /// Deletes a household and everything in it, in one transaction.
    func delete(householdID: String) async throws(HouseholdFailure)
}
