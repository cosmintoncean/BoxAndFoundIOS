import Foundation

/// What `get_invite_preview` returns: enough to decide before joining.
struct InvitePreview: Equatable, Sendable {
    let householdID: String
    let householdName: String?
    let ownerName: String?
    let memberCount: Int
    let isAlreadyMember: Bool
}

/// A member as `get_household_members` returns them.
struct HouseholdMember: Equatable, Identifiable, Sendable {
    let userID: String
    let displayName: String?
    let email: String?

    var id: String { userID }
}

/// Why a household operation did not happen.
///
/// Separate from `InventoryFailure` because two of these cases have no
/// inventory equivalent, and both are worth telling a person apart:
/// a code that matches nothing, and a server missing the function that makes
/// deletion atomic.
enum HouseholdFailure: Error, Equatable, Sendable {
    case network
    /// No household has that invite code.
    case unknownInviteCode
    /// `delete_household` is not installed on the project.
    ///
    /// Fails loudly rather than falling back to deleting the rows one by one
    /// from here. That sequence is not atomic: interrupted part-way it leaves
    /// orphaned rooms, boxes, items, layouts and nudges behind, with no way to
    /// tell how far it got. Quietly reintroducing the web client's bug would
    /// be worse than an error naming the migration to run.
    case deleteFunctionMissing
    case unknown(detail: String?)
}
