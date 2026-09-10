import Foundation

/// Where a search term hit, so a screen can say why a box is in the results.
struct BoxMatch: Equatable, Identifiable, Sendable {
    let box: Box
    let nameMatched: Bool
    let locationMatched: Bool
    let matchingItems: [BoxItem]

    var id: String { box.id }
    var matched: Bool { nameMatched || locationMatched || !matchingItems.isEmpty }
}

/// One room heading plus the boxes under it.
struct RoomGroup: Equatable, Identifiable, Sendable {
    /// Nil for the group of boxes with no room — `boxes.room_id` is nullable.
    let room: Room?
    let matches: [BoxMatch]

    var id: String { room?.id ?? "" }
}

/// Search, ported from the web client's `renderBoxList`: a case-insensitive
/// substring across the box name, its location, and the names of its items.
///
/// Pure and client-side deliberately. Pushing it into PostgREST would need an
/// `or` across an embedded table, and the whole household is already in
/// memory — the web client works the same way, so results match exactly.
enum BoxSearch {

    static func match(_ box: Box, term: String) -> BoxMatch {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return BoxMatch(box: box, nameMatched: false, locationMatched: false, matchingItems: [])
        }
        return BoxMatch(
            box: box,
            nameMatched: contains(box.name, needle),
            locationMatched: contains(box.location, needle),
            matchingItems: box.items.filter { contains($0.name, needle) }
        )
    }

    static func filter(_ boxes: [Box], term: String) -> [BoxMatch] {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return boxes.map { match($0, term: "") }
        }
        return boxes.map { match($0, term: term) }.filter(\.matched)
    }

    /// Groups boxes under their room, in the order the web client renders
    /// them: rooms by name, the unassigned group last, boxes by name within
    /// each.
    static func groupByRoom(rooms: [Room], matches: [BoxMatch]) -> [RoomGroup] {
        let sortedRooms = rooms.sorted { InventorySort.key($0.name) < InventorySort.key($1.name) }
        let byRoom = Dictionary(grouping: matches) { $0.box.roomID }

        let roomGroups = sortedRooms.map { room in
            RoomGroup(room: room, matches: sortedByBoxName(byRoom[room.id] ?? []))
        }

        // Anything whose room_id is nil, or points at a room this household
        // can no longer see, still has to appear somewhere.
        let knownRoomIDs = Set(rooms.map(\.id))
        let unassigned = sortedByBoxName(
            matches.filter { $0.box.roomID.map { !knownRoomIDs.contains($0) } ?? true }
        )

        return unassigned.isEmpty ? roomGroups : roomGroups + [RoomGroup(room: nil, matches: unassigned)]
    }

    private static func contains(_ haystack: String?, _ needle: String) -> Bool {
        (haystack ?? "").lowercased().contains(needle)
    }

    private static func sortedByBoxName(_ matches: [BoxMatch]) -> [BoxMatch] {
        matches.sorted { InventorySort.key($0.box.name) < InventorySort.key($1.box.name) }
    }
}
