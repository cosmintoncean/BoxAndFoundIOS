import Foundation
import Testing
@testable import BoxAndFound

@Suite("Room layout")
struct RoomLayoutTests {

    @Test("A layout with nothing in it knows so")
    func emptiness() {
        #expect(RoomLayout().isEmpty)
        #expect(!RoomLayout(walls: [MapWall(x1: 0, y1: 0, x2: 10, y2: 0)]).isEmpty)
        #expect(!RoomLayout(boxes: ["b1": BoxToken(x: 1, y: 1)]).isEmpty)
        #expect(!RoomLayout(furniture: [MapFurniture(x: 1, y: 1)]).isEmpty)
    }

    /// The defaults are the web client's, and a map drawn there before these
    /// fields existed has to open here looking the same.
    @Test("Absent sizes fall back to what the web draws")
    func defaults() {
        #expect(MapWall().drawnThickness == 7)
        #expect(MapWall(thickness: 3).drawnThickness == 3)
        #expect(MapDoor().drawnWidth == 32)
        #expect(MapDoor(width: 60).drawnWidth == 60)
        #expect(BoxToken().drawnWidth == BoxToken.defaultSize)
        #expect(BoxToken(width: 20, height: 30).drawnHeight == 30)
    }

    @Test("A metre is what the web says it is")
    func scale() {
        // WALL_SNAP (40) x SQUARES_PER_UNIT (7).
        #expect(RoomLayout.unitsPerMetre == 280)
    }

    // MARK: - Bounds

    /// There is no rectangle around nothing, and a zero one would be divided
    /// by when fitting the map to a screen.
    @Test("Nothing drawn has no bounds")
    func emptyHasNoBounds() {
        #expect(MapBounds.around(RoomLayout()) == nil)
    }

    @Test("Walls and floors are measured corner to corner")
    func wallsAndFloors() {
        let layout = RoomLayout(
            walls: [MapWall(x1: 10, y1: 20, x2: 110, y2: 20)],
            floors: [[MapPoint(x: 0, y: 0), MapPoint(x: 50, y: 80)]]
        )
        let bounds = MapBounds.around(layout)
        #expect(bounds == MapBounds(minX: 0, minY: 0, maxX: 110, maxY: 80))
        #expect(bounds?.width == 110)
        #expect(bounds?.height == 80)
    }

    /// A token is anchored at its centre on the web, so half of it hangs off
    /// each side. Measuring from the anchor alone clips every box on the edge.
    @Test("A box token is measured around its centre, not from it")
    func tokensAreMeasuredAroundTheirCentre() {
        let layout = RoomLayout(boxes: ["b1": BoxToken(x: 100, y: 100, width: 40, height: 20)])
        #expect(MapBounds.around(layout) == MapBounds(minX: 80, minY: 90, maxX: 120, maxY: 110))
    }

    @Test("Furniture is measured from its corner outwards")
    func furnitureExtends() {
        let layout = RoomLayout(furniture: [MapFurniture(x: 10, y: 10, width: 30, height: 5)])
        #expect(MapBounds.around(layout) == MapBounds(minX: 10, minY: 10, maxX: 40, maxY: 15))
    }

    @Test("Doors count towards the extent")
    func doorsCount() {
        let layout = RoomLayout(doors: [MapDoor(x: -50, y: 5)])
        #expect(MapBounds.around(layout)?.minX == -50)
    }

    @Test("Negative coordinates are not clamped away")
    func negativesSurvive() {
        let layout = RoomLayout(walls: [MapWall(x1: -100, y1: -60, x2: 0, y2: 0)])
        #expect(MapBounds.around(layout) == MapBounds(minX: -100, minY: -60, maxX: 0, maxY: 0))
    }

    @Test("Everything on the map is included at once")
    func everythingTogether() {
        let layout = RoomLayout(
            boxes: ["b1": BoxToken(x: 0, y: 0, width: 10, height: 10)],
            walls: [MapWall(x1: 200, y1: 0, x2: 200, y2: 100)],
            doors: [MapDoor(x: 100, y: -40)],
            floors: [[MapPoint(x: -30, y: 0)]],
            furniture: [MapFurniture(x: 0, y: 150, width: 10, height: 10)]
        )
        // minY is the door at -40, not the token's top edge at -5.
        #expect(MapBounds.around(layout) == MapBounds(minX: -30, minY: -40, maxX: 200, maxY: 160))
    }
}
