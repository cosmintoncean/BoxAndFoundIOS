import Foundation

/// Storage as a tree.
///
/// A "place" is anything that physically holds something: a box, a wardrobe, a
/// drawer, a shelf. They are rows in one table linked by `parent_id`, so a box
/// is a place of type `box` — the one kind that usually holds items rather
/// than other places.
///
///     Room → Wardrobe → Drawer 2 → Box 14 → Box 14A → "PS5 controller"
///
/// Rooms are not places: a room is its own table and always the root, which is
/// why every place also carries the room it ultimately sits in. The server
/// resolves that column on every write (see the web repository's
/// `MIGRATION_storage_containers.sql`), which is what lets the box list, the
/// room map and search go on grouping by room without knowing the tree exists.
///
/// Ported from the web client's `places.js` by way of the Android client's
/// `Places`, so all three agree on what is inside what. Pure: no repositories,
/// no concurrency — a household's places are already loaded in full by the
/// time any of this is asked.
enum Places {

    /// The one kind that is not furniture someone put in a room.
    static let typeBox = "box"

    /// A room is not a place, so it cannot hold items — `box_items` hangs off
    /// a place id. A room that needs loose items gets one hidden place of this
    /// type to hold them, made by the web client the first time something is
    /// put in the room itself.
    ///
    /// It is never shown: as far as anyone looking at the app is concerned, it
    /// is the room.
    static let typeRoomItems = "room"

    /// Mirrors the database trigger's cap, so the message comes before the
    /// request.
    static let maxDepth = 8

    /// Furniture that holds boxes, in the order it is offered. Free text to
    /// the database — the catalogue lives in the clients — so an unknown type
    /// from a newer build is still a container, not an error.
    static let containerTypes = [
        "wardrobe", "shelving", "shelf", "cabinet", "drawer",
        "cupboard", "chest", "rack", "closet", "crate", "other",
    ]

    static func isBox(_ place: Box) -> Bool { place.type == typeBox }

    static func isRoomItems(_ place: Box) -> Bool { place.type == typeRoomItems }

    /// A container someone made, as against the hidden holder for a room's own
    /// items. Everything that lists or offers containers means this one.
    static func isContainer(_ place: Box) -> Bool { !isBox(place) && !isRoomItems(place) }

    /// id → place, for walking up and down without rescanning the list.
    static func index(_ places: [Box]) -> [String: Box] {
        Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// What sits directly inside `parentID` — or directly in `roomID` when no
    /// parent is given, which is the room's own top level.
    static func children(_ places: [Box], parentID: String?, roomID: String? = nil) -> [Box] {
        places
            // The holder for a room's loose items is not one of the room's
            // things.
            .filter { !isRoomItems($0) }
            .filter { place in
                if let parentID { return place.parentID == parentID }
                return place.parentID == nil && place.roomID == roomID
            }
    }

    /// The containers between the room and this place, outermost first, not
    /// counting the place itself.
    ///
    /// Defended against a cycle rather than trusting the rows: the database
    /// rejects one, but a half-applied edit or a row from another client must
    /// not be able to spin the screen forever.
    static func ancestors(of place: Box?, index: [String: Box]) -> [Box] {
        guard let place else { return [] }
        var out: [Box] = []
        var seen: Set<String> = [place.id]
        var current = place.parentID.flatMap { index[$0] }
        while let node = current, out.count < maxDepth, seen.insert(node.id).inserted {
            out.append(node)
            current = node.parentID.flatMap { index[$0] }
        }
        return out.reversed()
    }

    /// 0 directly in a room, 1 inside one container, and so on.
    static func depth(of place: Box?, index: [String: Box]) -> Int {
        ancestors(of: place, index: index).count
    }

    /// Where this physically is, room first: Attic › Wardrobe › Drawer 2 ›
    /// Box 14.
    ///
    /// A place with no room — or one whose room is gone — simply starts at its
    /// outermost container, so the path never carries a blank first step.
    static func path(
        of place: Box?,
        index: [String: Box],
        rooms: [Room],
        /// What an unnamed box or container is called, worded by the caller.
        unnamed: String = "Unnamed"
    ) -> [String] {
        guard let place else { return [] }
        var parts: [String] = []
        if let room = rooms.first(where: { $0.id == place.roomID }),
           let name = room.name,
           !name.trimmed.isEmpty {
            parts.append(name)
        }
        for ancestor in ancestors(of: place, index: index) {
            parts.append(displayName(of: ancestor, unnamed: unnamed))
        }
        parts.append(displayName(of: place, unnamed: unnamed))
        return parts
    }

    /// Everything inside this place at any depth — what a delete would affect,
    /// and what a container's count is counting.
    static func descendants(of place: Box?, in places: [Box]) -> [Box] {
        guard let place else { return [] }
        var byParent: [String: [Box]] = [:]
        for candidate in places {
            guard let parent = candidate.parentID else { continue }
            byParent[parent, default: []].append(candidate)
        }

        var out: [Box] = []
        var seen: Set<String> = [place.id]
        var queue = byParent[place.id] ?? []
        var cursor = 0
        while cursor < queue.count {
            let next = queue[cursor]
            cursor += 1
            guard seen.insert(next.id).inserted else { continue }
            out.append(next)
            queue.append(contentsOf: byParent[next.id] ?? [])
        }
        return out
    }

    /// What is inside a place at any depth: the boxes, the containers, and the
    /// items that are in neither — sitting in this container or in one inside
    /// it.
    ///
    /// An item in a box is counted by its box. A wardrobe holding two boxes of
    /// forty baubles reads as two boxes, not eighty things; the loose ones are
    /// the only items nothing else would account for.
    static func contents(of place: Box?, in places: [Box]) -> PlaceContents {
        guard let place else { return PlaceContents() }
        let inside = descendants(of: place, in: places)
        let boxes = inside.filter(isBox).count
        let loose = ([place] + inside)
            .filter { !isBox($0) }
            .reduce(0) { $0 + $1.items.count }
        return PlaceContents(
            boxes: boxes,
            containers: inside.count - boxes,
            looseItems: loose
        )
    }

    /// The items sitting in this place itself rather than in a box inside it.
    ///
    /// For a room that is the hidden holder's items; for a container, its own.
    /// An item in a box belongs to that box and is not counted here.
    static func looseItems(of place: Box?) -> [BoxItem] {
        guard let place, !isBox(place) else { return [] }
        return place.items
    }

    /// The hidden holder for a room's own items, if that room has one yet.
    static func roomItemsHolder(in places: [Box], roomID: String?) -> Box? {
        places.first { isRoomItems($0) && $0.roomID == roomID }
    }

    /// Where a container's contents go when it is deleted: one level up, into
    /// whatever it was sitting in. Losing a wardrobe must not mean losing what
    /// was in it, and the room stays the same either way.
    static func parentAfterDeleting(_ container: Box) -> String? { container.parentID }

    private static func displayName(of place: Box, unnamed: String) -> String {
        let name = place.name ?? ""
        return name.trimmed.isEmpty ? unnamed : name
    }
}

/// What a container holds, split the way someone opening it would see it.
struct PlaceContents: Equatable, Sendable {
    var boxes: Int = 0
    var containers: Int = 0
    var looseItems: Int = 0

    var total: Int { boxes + containers + looseItems }
}
