import Foundation

/// The inventory, as the system understands it.
///
/// Mirrors of the Postgres tables, ported from the Android client's `Models`.
/// Column names were confirmed there against the live schema rather than
/// inferred from the migrations, and the mapping from those column names onto
/// these lives in the data layer, not here — nothing in this file knows that
/// `roomID` is spelled `room_id` on the wire.
///
/// Every table is RLS-scoped by household membership, so these carry no
/// ownership checks of their own beyond `Household.isOwned(by:)`.

struct Household: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?
    let inviteCode: String?
    let ownerID: String?

    /// Owners are not rows in `household_members`, so ownership is a field
    /// check rather than a membership one.
    func isOwned(by userID: String) -> Bool { ownerID == userID }
}

struct Room: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?
    let householdID: String?
}

struct BoxItem: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?
    let quantity: Int
    let position: Int
    let isTaken: Bool
    let takenAt: String?
    let takenBy: String?

    init(
        id: String,
        name: String? = nil,
        quantity: Int = 1,
        position: Int = 0,
        isTaken: Bool = false,
        takenAt: String? = nil,
        takenBy: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.position = position
        self.isTaken = isTaken
        self.takenAt = takenAt
        self.takenBy = takenBy
    }
}

struct Box: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?
    let imageURL: String?
    let location: String?
    /// A string key, not an image: one of `BoxIcons.keys`. A box created with
    /// a key another client does not know renders as that client's fallback,
    /// which is why all three ship the same twelve.
    let icon: String?
    let roomID: String?
    let householdID: String?
    /// Always in display order. PostgREST does not sort embedded rows, so the
    /// ordering the web client relies on is applied here, once, at
    /// construction — rather than by every reader remembering to.
    let items: [BoxItem]

    init(
        id: String,
        name: String? = nil,
        imageURL: String? = nil,
        location: String? = nil,
        icon: String? = nil,
        roomID: String? = nil,
        householdID: String? = nil,
        items: [BoxItem] = []
    ) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.location = location
        self.icon = icon
        self.roomID = roomID
        self.householdID = householdID
        self.items = items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            // Name as a tiebreak so the list cannot reshuffle between reads.
            return InventorySort.key($0.name) < InventorySort.key($1.name)
        }
    }
}

/// Sorting shared by boxes, rooms and items.
enum InventorySort {
    /// Case-insensitive, with anything unnamed last. A missing name should not
    /// jump to the top of a list.
    static func key(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return last }
        return name.lowercased()
    }

    /// Sorts after every realistic name. U+FFFF is unassigned and permanent.
    private static let last = "\u{FFFF}"
}
