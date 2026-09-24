import Foundation
import Testing
@testable import BoxAndFound

@Suite("Map projection")
struct MapProjectionTests {

    private func drawing(
        _ layout: RoomLayout,
        names: [String: String] = [:],
        unit: MeasurementUnit = .metric
    ) -> RoomMapViewState.Drawing? {
        MapProjection.drawing(from: layout, boxNames: names, unit: unit)
    }

    /// A square room, 1120 x 840 units — four metres by three.
    private var room: RoomLayout {
        RoomLayout(
            walls: [
                MapWall(x1: 0, y1: 0, x2: 1120, y2: 0),
                MapWall(x1: 0, y1: 840, x2: 1120, y2: 840),
            ]
        )
    }

    @Test("Nothing to draw produces no drawing")
    func nothingToDraw() {
        #expect(drawing(RoomLayout()) == nil)
    }

    @Test("Corners land on the corners")
    func normalisation() {
        let result = drawing(room)
        #expect(result?.walls.first?.from == .init(x: 0, y: 0))
        #expect(result?.walls.first?.to == .init(x: 1, y: 0))
        #expect(result?.walls.last?.to == .init(x: 1, y: 1))
    }

    @Test("The aspect ratio is width over height")
    func aspect() {
        #expect(drawing(room)?.aspectRatio == 1120.0 / 840.0)
    }

    /// A map can be one straight wall, which has no height at all. Dividing by
    /// that zero is how every coordinate becomes NaN and the canvas silently
    /// draws nothing — the same thing a failed load looks like.
    @Test("A layout with no height does not divide by zero")
    func degenerateHeight() {
        let flat = RoomLayout(walls: [MapWall(x1: 0, y1: 50, x2: 500, y2: 50)])
        guard let result = drawing(flat) else {
            Issue.record("Expected a drawing")
            return
        }
        #expect(result.aspectRatio.isFinite)
        #expect(result.walls.allSatisfy { $0.from.y.isFinite && $0.to.y.isFinite })
    }

    @Test("A layout with no width does not divide by zero either")
    func degenerateWidth() {
        let upright = RoomLayout(walls: [MapWall(x1: 20, y1: 0, x2: 20, y2: 500)])
        guard let result = drawing(upright) else {
            Issue.record("Expected a drawing")
            return
        }
        #expect(result.aspectRatio.isFinite)
        #expect(result.walls.allSatisfy { $0.from.x.isFinite && $0.thickness.isFinite })
    }

    /// Sizes scale with width alone. Scaling them per-axis would make every
    /// token an oval the moment the room was not square.
    @Test("Sizes are a fraction of the width, not of each axis")
    func sizesUseWidth() {
        let layout = RoomLayout(
            boxes: ["b1": BoxToken(x: 560, y: 420, width: 112, height: 112)],
            walls: room.walls
        )
        let token = drawing(layout)?.boxes.first
        #expect(token?.width == 0.1)
        #expect(token?.height == 0.1)
    }

    @Test("A token sits where it was put")
    func tokenPosition() {
        let layout = RoomLayout(boxes: ["b1": BoxToken(x: 560, y: 420)], walls: room.walls)
        #expect(drawing(layout)?.boxes.first?.centre == .init(x: 0.5, y: 0.5))
    }

    @Test("Tokens are named from the inventory, and unnamed when it has no name")
    func tokenLabels() {
        let layout = RoomLayout(boxes: ["b1": BoxToken(x: 0, y: 0)], walls: room.walls)
        #expect(drawing(layout, names: ["b1": "Winter Clothes"])?.boxes.first?.label == "Winter Clothes")
        #expect(drawing(layout)?.boxes.first?.label == "")
    }

    /// A dictionary hands its values back in no particular order, so an
    /// unsorted list makes SwiftUI rebuild every token on each reload.
    @Test("Tokens come out in a stable order")
    func tokenOrderIsStable() {
        let layout = RoomLayout(
            boxes: [
                "c": BoxToken(x: 1, y: 1),
                "a": BoxToken(x: 2, y: 2),
                "b": BoxToken(x: 3, y: 3),
            ],
            walls: room.walls
        )
        #expect(drawing(layout)?.boxes.map(\.id) == ["a", "b", "c"])
    }

    @Test("Doors keep the angle the web stored")
    func doorAngle() {
        let layout = RoomLayout(doors: [MapDoor(x: 0, y: 0, angle: 90)], walls: room.walls)
        #expect(drawing(layout)?.doors.first?.angle == 90)
    }

    // MARK: - The size note

    @Test("The size note reads in metres")
    func metricNote() {
        #expect(drawing(room)?.sizeNote == "4.0 m × 3.0 m")
    }

    @Test("The size note reads in feet when asked")
    func imperialNote() {
        // Four metres is a touch over thirteen feet.
        #expect(drawing(room, unit: .imperial)?.sizeNote == "13.1 ft × 9.8 ft")
    }

    @Test("A metre is 280 units, as the web draws it")
    func scaleMatchesTheWeb() {
        let oneMetre = MapBounds(minX: 0, minY: 0, maxX: 280, maxY: 280)
        #expect(MapProjection.sizeNote(bounds: oneMetre, unit: .metric) == "1.0 m × 1.0 m")
    }
}
