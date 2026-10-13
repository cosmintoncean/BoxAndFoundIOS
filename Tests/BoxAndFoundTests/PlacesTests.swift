import Foundation
import Testing
@testable import BoxAndFound

/// The storage tree, ported from the Android client's `PlacesTest` so the two
/// cannot drift: both answer to the web's `places.js`, and a disagreement
/// about what is inside what would show up as one client losing a wardrobe.
@Suite("Places")
struct PlacesTests {

    private func place(
        _ id: String,
        name: String? = nil,
        type: String = Places.typeBox,
        parentID: String? = nil,
        roomID: String? = "room-1",
        items: [BoxItem] = []
    ) -> Box {
        Box(
            id: id,
            name: name ?? id,
            roomID: roomID,
            householdID: "hh",
            items: items,
            type: type,
            parentID: parentID
        )
    }

    private func item(_ id: String, taken: Bool = false, tags: [String] = []) -> BoxItem {
        BoxItem(id: id, name: id, isTaken: taken, tags: tags)
    }

    /// Room 1 → Wardrobe → Drawer → Box; one box straight in the room.
    private var tree: [Box] {
        [
            place("wardrobe", type: "wardrobe"),
            place("drawer", type: "drawer", parentID: "wardrobe"),
            place("boxed", parentID: "drawer"),
            place("loose-box"),
        ]
    }

    @Test("A box is the one kind that is not furniture")
    func kinds() {
        #expect(Places.isBox(place("b")))
        #expect(!Places.isContainer(place("b")))
        #expect(Places.isContainer(place("w", type: "wardrobe")))
        #expect(Places.isRoomItems(place("r", type: Places.typeRoomItems)))
        #expect(!Places.isContainer(place("r", type: Places.typeRoomItems)))
    }

    @Test("A room's top level is what has no container above it")
    func topLevel() {
        let top = Places.children(tree, parentID: nil, roomID: "room-1")
        #expect(top.map(\.id).sorted() == ["loose-box", "wardrobe"])
    }

    @Test("What is inside a container is what names it as parent")
    func children() {
        #expect(Places.children(tree, parentID: "wardrobe").map(\.id) == ["drawer"])
        #expect(Places.children(tree, parentID: "drawer").map(\.id) == ["boxed"])
        #expect(Places.children(tree, parentID: "boxed").isEmpty)
    }

    @Test("The holder for a room's own items is never one of the room's things")
    func holderIsHidden() {
        let places = tree + [place("holder", type: Places.typeRoomItems)]
        let top = Places.children(places, parentID: nil, roomID: "room-1")
        #expect(!top.contains { $0.id == "holder" })
    }

    @Test("Ancestors run outermost first and leave out the place itself")
    func ancestors() {
        let found = Places.ancestors(
            of: tree.first { $0.id == "boxed" },
            index: Places.index(tree)
        )
        #expect(found.map(\.id) == ["wardrobe", "drawer"])
    }

    @Test("Depth counts the containers above it")
    func depth() {
        let index = Places.index(tree)
        #expect(Places.depth(of: tree.first { $0.id == "loose-box" }, index: index) == 0)
        #expect(Places.depth(of: tree.first { $0.id == "drawer" }, index: index) == 1)
        #expect(Places.depth(of: tree.first { $0.id == "boxed" }, index: index) == 2)
    }

    @Test("The path reads from the room inwards")
    func path() {
        let rooms = [Room(id: "room-1", name: "Attic", householdID: "hh")]
        let found = Places.path(
            of: tree.first { $0.id == "boxed" },
            index: Places.index(tree),
            rooms: rooms
        )
        #expect(found == ["Attic", "wardrobe", "drawer", "boxed"])
    }

    /// A place whose room is gone starts at its outermost container instead.
    @Test("A path never starts with a blank step")
    func pathWithoutARoom() {
        let found = Places.path(
            of: tree.first { $0.id == "drawer" },
            index: Places.index(tree),
            rooms: []
        )
        #expect(found == ["wardrobe", "drawer"])
    }

    @Test("An unnamed place is called whatever the caller calls it")
    func unnamed() {
        let blank = [place("b", name: "   ")]
        let found = Places.path(
            of: blank[0],
            index: Places.index(blank),
            rooms: [],
            unnamed: "Untitled"
        )
        #expect(found == ["Untitled"])
    }

    @Test("Descendants reach all the way down")
    func descendants() {
        let found = Places.descendants(of: tree.first { $0.id == "wardrobe" }, in: tree)
        #expect(found.map(\.id).sorted() == ["boxed", "drawer"])
    }

    /// The database rejects a cycle, but a half-applied edit or a row from
    /// another client must not be able to spin the screen forever.
    @Test("A cycle is survived rather than trusted")
    func cycle() {
        let looped = [
            place("a", type: "shelf", parentID: "b"),
            place("b", type: "shelf", parentID: "a"),
        ]
        let index = Places.index(looped)
        let found = Places.ancestors(of: looped[0], index: index)
        #expect(found.count <= Places.maxDepth)
        #expect(Places.descendants(of: looped[0], in: looped).count <= looped.count)
    }

    @Test("Deleting a container leaves its contents one level up")
    func deletion() {
        let drawer = tree.first { $0.id == "drawer" }
        #expect(Places.parentAfterDeleting(drawer!) == "wardrobe")
        let wardrobe = tree.first { $0.id == "wardrobe" }
        #expect(Places.parentAfterDeleting(wardrobe!) == nil)
    }

    @Test("A room's loose items hang off its holder")
    func looseItemsOfARoom() {
        let holder = place(
            "holder",
            type: Places.typeRoomItems,
            items: [item("torch"), item("stepladder")]
        )
        let places = tree + [holder]
        #expect(Places.roomItemsHolder(in: places, roomID: "room-1")?.id == "holder")
        #expect(Places.looseItems(of: holder).map(\.id) == ["stepladder", "torch"])
        // A box's items belong to the box, not to whatever it sits in.
        #expect(Places.looseItems(of: tree.first { $0.id == "boxed" }).isEmpty)
    }

    /// A wardrobe holding two boxes of forty baubles reads as two boxes, not
    /// eighty things.
    @Test("A container counts its boxes, its furniture and what is loose in it")
    func contents() {
        let places = [
            place("wardrobe", type: "wardrobe", items: [item("hanger")]),
            place("drawer", type: "drawer", parentID: "wardrobe", items: [item("sock")]),
            place("boxed", parentID: "drawer", items: [item("bauble"), item("bauble-2")]),
        ]
        let found = Places.contents(of: places[0], in: places)
        #expect(found.boxes == 1)
        #expect(found.containers == 1)
        #expect(found.looseItems == 2)
        #expect(found.total == 4)
    }

    @Test("An empty container holds nothing at all")
    func emptyContents() {
        let empty = place("w", type: "wardrobe")
        #expect(Places.contents(of: empty, in: [empty]) == PlaceContents())
        #expect(Places.contents(of: nil, in: []).total == 0)
    }
}
