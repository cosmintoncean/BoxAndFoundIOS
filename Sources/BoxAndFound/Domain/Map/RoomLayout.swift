import Foundation

/// The saved room map, exactly as `room_layouts.layout` stores it.
///
/// The web client's own header describes the shape:
///
///     { boxes:{[id]:{x,y}}, walls:[{x1,y1,x2,y2}], doors:[{x,y,angle}],
///       floors:[[{x,y},...]] }
///
/// plus `furniture`, added later. Every field defaults because a layout saved
/// before a feature existed simply omits it — the web's `ensureLayout()` fills
/// the same gaps at load time, and a map drawn on Android must still open here.
///
/// Coordinates are canvas units, not pixels or metres. One metre is
/// `unitsPerMetre`; only a scale bar needs that, but it is why the numbers
/// look large.
struct RoomLayout: Equatable, Sendable {
    var boxes: [String: BoxToken] = [:]
    var walls: [MapWall] = []
    var doors: [MapDoor] = []
    /// Each floor is a polygon: a list of points, filled.
    var floors: [[MapPoint]] = []
    var furniture: [MapFurniture] = []

    var isEmpty: Bool {
        boxes.isEmpty && walls.isEmpty && doors.isEmpty && floors.isEmpty && furniture.isEmpty
    }

    /// `WALL_SNAP` (40) × `SQUARES_PER_UNIT` (7) in the web client.
    static let unitsPerMetre: Double = 280
}

struct MapPoint: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
}

struct MapWall: Equatable, Sendable {
    var x1: Double = 0
    var y1: Double = 0
    var x2: Double = 0
    var y2: Double = 0
    /// The web defaults to 7 (medium) when absent.
    var thickness: Double?

    var drawnThickness: Double { thickness ?? 7 }
}

struct MapDoor: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    /// Degrees, matching the SVG `rotate(angle)` the web applies.
    var angle: Double = 0
    /// `DOOR_DEFAULT_W` is 32 when absent.
    var width: Double?

    var drawnWidth: Double { width ?? 32 }
}

struct MapFurniture: Equatable, Sendable {
    var type: String?
    var label: String?
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}

/// Where a box sits on the map. `width`/`height` are set only if it was resized.
struct BoxToken: Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double?
    var height: Double?

    static let defaultSize: Double = 44

    var drawnWidth: Double { width ?? Self.defaultSize }
    var drawnHeight: Double { height ?? Self.defaultSize }
}

/// The rectangle a layout actually occupies.
///
/// Pure, and the thing a view needs before it can draw anything: the canvas
/// units are arbitrary and a map may sit anywhere in them, so fitting one to a
/// screen means knowing its extent first. Getting this wrong shows up as a map
/// drawn off-screen, which looks exactly like a map that failed to load.
struct MapBounds: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    /// Nil for a layout with nothing in it — there is no rectangle around
    /// nothing, and returning a zero one would divide by it later.
    static func around(_ layout: RoomLayout) -> MapBounds? {
        var xs: [Double] = []
        var ys: [Double] = []

        for wall in layout.walls {
            xs.append(contentsOf: [wall.x1, wall.x2])
            ys.append(contentsOf: [wall.y1, wall.y2])
        }
        for floor in layout.floors {
            xs.append(contentsOf: floor.map(\.x))
            ys.append(contentsOf: floor.map(\.y))
        }
        for door in layout.doors {
            xs.append(door.x)
            ys.append(door.y)
        }
        // A token's anchor is its centre on the web, so half of it hangs off
        // each side; a bound taken from the anchor alone clips them.
        for token in layout.boxes.values {
            xs.append(contentsOf: [token.x - token.drawnWidth / 2, token.x + token.drawnWidth / 2])
            ys.append(contentsOf: [token.y - token.drawnHeight / 2, token.y + token.drawnHeight / 2])
        }
        for piece in layout.furniture {
            xs.append(contentsOf: [piece.x, piece.x + piece.width])
            ys.append(contentsOf: [piece.y, piece.y + piece.height])
        }

        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return nil }

        return MapBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
