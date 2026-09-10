import Testing
@testable import BoxAndFound

@Suite("Box search and grouping")
struct BoxSearchTests {

    private func box(
        _ id: String,
        name: String? = nil,
        location: String? = nil,
        room: String? = nil,
        items: [String] = []
    ) -> Box {
        Box(
            id: id,
            name: name,
            location: location,
            roomID: room,
            items: items.enumerated().map { BoxItem(id: "\(id)-\($0.offset)", name: $0.element) }
        )
    }

    // MARK: - Matching

    @Test("Hits box name, location and item names alike, ignoring case")
    func matchesEverywhere() {
        let winter = box("1", name: "Winter Clothes", location: "Attic", items: ["Scarf", "Gloves"])

        #expect(BoxSearch.match(winter, term: "winter").nameMatched)
        #expect(BoxSearch.match(winter, term: "WINTER").nameMatched)
        #expect(BoxSearch.match(winter, term: "attic").locationMatched)
        #expect(BoxSearch.match(winter, term: "glo").matchingItems.map(\.name) == ["Gloves"])
    }

    @Test("Says where it hit, so a screen can explain itself")
    func reportsWhere() {
        let match = BoxSearch.match(box("1", name: "Tools", location: "Garage"), term: "tools")
        #expect(match.nameMatched)
        #expect(!match.locationMatched)
        #expect(match.matchingItems.isEmpty)
        #expect(match.matched)
    }

    @Test("An empty or whitespace term keeps every box and highlights nothing")
    func emptyTermKeepsEverything() {
        let boxes = [box("1", name: "A"), box("2", name: "B")]
        for term in ["", "   ", "\n"] {
            let matches = BoxSearch.filter(boxes, term: term)
            #expect(matches.count == 2)
            #expect(matches.allSatisfy { !$0.nameMatched && $0.matchingItems.isEmpty })
        }
    }

    @Test("A term that hits nothing returns nothing")
    func filtersOutMisses() {
        let boxes = [box("1", name: "Tools", items: ["Hammer"]), box("2", name: "Books")]
        #expect(BoxSearch.filter(boxes, term: "hammer").map(\.box.id) == ["1"])
        #expect(BoxSearch.filter(boxes, term: "zzz").isEmpty)
    }

    @Test("A term is trimmed before it is used")
    func trimsTerm() {
        #expect(BoxSearch.filter([box("1", name: "Tools")], term: "  tools  ").count == 1)
    }

    // MARK: - Grouping

    @Test("Rooms come in name order, boxes in name order within them")
    func ordersRoomsAndBoxes() {
        let rooms = [
            Room(id: "r2", name: "Attic", householdID: "h"),
            Room(id: "r1", name: "Garage", householdID: "h"),
        ]
        let matches = BoxSearch.filter(
            [box("b1", name: "Zebra", room: "r1"),
             box("b2", name: "apple", room: "r1"),
             box("b3", name: "Mid", room: "r2")],
            term: ""
        )

        let groups = BoxSearch.groupByRoom(rooms: rooms, matches: matches)
        #expect(groups.map(\.room?.name) == ["Attic", "Garage"])
        #expect(groups[1].matches.map(\.box.name) == ["apple", "Zebra"])
    }

    @Test("Boxes with no room land in a trailing group of their own")
    func unassignedGoesLast() {
        let rooms = [Room(id: "r1", name: "Garage", householdID: "h")]
        let matches = BoxSearch.filter(
            [box("b1", name: "Tools", room: "r1"), box("b2", name: "Loose")],
            term: ""
        )

        let groups = BoxSearch.groupByRoom(rooms: rooms, matches: matches)
        #expect(groups.count == 2)
        #expect(groups.last?.room == nil)
        #expect(groups.last?.matches.map(\.box.name) == ["Loose"])
    }

    /// A box can outlive the room it points at — a room deleted elsewhere, or
    /// one this member cannot see. Dropping it would make a box vanish from
    /// the only screen that lists it.
    @Test("A box pointing at a room that is gone still appears")
    func danglingRoomStillShows() {
        let matches = BoxSearch.filter([box("b1", name: "Orphan", room: "deleted-room")], term: "")
        let groups = BoxSearch.groupByRoom(rooms: [], matches: matches)
        #expect(groups.count == 1)
        #expect(groups[0].room == nil)
        #expect(groups[0].matches.map(\.box.name) == ["Orphan"])
    }

    @Test("No unassigned group appears when every box has a room")
    func noEmptyTrailingGroup() {
        let rooms = [Room(id: "r1", name: "Garage", householdID: "h")]
        let matches = BoxSearch.filter([box("b1", name: "Tools", room: "r1")], term: "")
        #expect(BoxSearch.groupByRoom(rooms: rooms, matches: matches).count == 1)
    }

    @Test("An unnamed box sorts last rather than first")
    func unnamedSortsLast() {
        let matches = BoxSearch.filter([box("b1"), box("b2", name: "Apples")], term: "")
        let groups = BoxSearch.groupByRoom(rooms: [], matches: matches)
        #expect(groups[0].matches.map(\.box.id) == ["b2", "b1"])
    }
}
