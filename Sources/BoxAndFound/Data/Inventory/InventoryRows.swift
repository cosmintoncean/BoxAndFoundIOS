import Foundation

/// The wire shapes, and the only place the database's column names appear.
///
/// Kept separate from the domain models so that `Box` never has to be
/// `Codable` and never has to carry `CodingKeys` naming a Postgres column. The
/// cost is a mapping function per table; the benefit is that renaming a column
/// touches this file and nothing else.
struct HouseholdRow: Decodable {
    let id: String
    let name: String?
    let invite_code: String?
    let owner_id: String?

    var domain: Household {
        Household(id: id, name: name, inviteCode: invite_code, ownerID: owner_id)
    }
}

/// `households` reached through the membership join table.
struct MembershipRow: Decodable {
    let household: HouseholdRow?
}

struct RoomRow: Decodable {
    let id: String
    let name: String?
    let household_id: String?

    var domain: Room {
        Room(id: id, name: name, householdID: household_id)
    }
}

struct BoxItemRow: Decodable {
    let id: String
    let name: String?
    let qty: Int?
    let position: Int?
    let taken: Bool?
    let taken_at: String?
    let taken_by: String?

    var domain: BoxItem {
        // The defaults match the column defaults: a row written by an older
        // client, or by the web client before a migration, still reads.
        BoxItem(
            id: id,
            name: name,
            quantity: qty ?? 1,
            position: position ?? 0,
            isTaken: taken ?? false,
            takenAt: taken_at,
            takenBy: taken_by
        )
    }
}

struct BoxRow: Decodable {
    let id: String
    let name: String?
    let image_url: String?
    let location: String?
    let icon: String?
    let room_id: String?
    let household_id: String?
    let box_items: [BoxItemRow]?

    var domain: Box {
        Box(
            id: id,
            name: name,
            imageURL: image_url,
            location: location,
            icon: icon,
            roomID: room_id,
            householdID: household_id,
            items: (box_items ?? []).map(\.domain)
        )
    }
}
