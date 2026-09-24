import Foundation

/// Everything the room map draws.
///
/// Geometry arrives **normalised**: every coordinate is a fraction of the
/// map's own bounding box, and every size a fraction of its width. The view
/// multiplies by the rectangle it ends up with and draws. That split is
/// deliberate — fitting a map to a screen is arithmetic worth testing, and the
/// presenter cannot know the screen, so it does the part that does not need
/// one and hands over numbers that work at any size.
struct RoomMapViewState: Equatable {

    /// A point as a fraction of the bounding box: (0,0) top-left, (1,1)
    /// bottom-right.
    struct NormalPoint: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    struct Segment: Equatable, Identifiable {
        let id: Int
        let from: NormalPoint
        let to: NormalPoint
        /// A fraction of the bounding box width.
        let thickness: Double
    }

    struct Polygon: Equatable, Identifiable {
        let id: Int
        let points: [NormalPoint]
    }

    struct DoorMark: Equatable, Identifiable {
        let id: Int
        let centre: NormalPoint
        let width: Double
        /// Degrees, as the web stores them.
        let angle: Double
    }

    struct BoxMark: Equatable, Identifiable {
        /// The real box id, so tapping one can open it.
        let id: String
        let label: String
        let centre: NormalPoint
        let width: Double
        let height: Double
    }

    struct FurnitureMark: Equatable, Identifiable {
        let id: Int
        let label: String?
        let origin: NormalPoint
        let width: Double
        let height: Double
    }

    struct Drawing: Equatable {
        /// Width over height, so the view can letterbox without distorting.
        let aspectRatio: Double
        let floors: [Polygon]
        let walls: [Segment]
        let doors: [DoorMark]
        let furniture: [FurnitureMark]
        let boxes: [BoxMark]
        /// "4.2 m × 3.0 m", or the same in feet.
        let sizeNote: String
    }

    enum Content: Equatable {
        case loading
        case empty(message: String)
        case failed(message: String)
        case map(Drawing)
    }

    var title: String
    var content: Content
}
