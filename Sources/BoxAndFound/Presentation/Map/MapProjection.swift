import Foundation

/// Turns a saved layout into something drawable at any size.
///
/// Pure, and tested directly: this is where a map ends up off-screen, upside
/// down or squashed, and every one of those failures looks identical from
/// here — a blank canvas.
enum MapProjection {

    /// Nil when there is nothing to draw.
    static func drawing(
        from layout: RoomLayout,
        boxNames: [String: String],
        unit: MeasurementUnit
    ) -> RoomMapViewState.Drawing? {
        guard let bounds = MapBounds.around(layout) else { return nil }

        // A map can be a single straight wall, which has no height at all.
        // Dividing by that zero is how the whole drawing becomes NaN and the
        // canvas silently renders nothing.
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)

        func point(_ x: Double, _ y: Double) -> RoomMapViewState.NormalPoint {
            RoomMapViewState.NormalPoint(
                x: (x - bounds.minX) / width,
                y: (y - bounds.minY) / height
            )
        }

        // Sizes scale with the width alone, so a token stays square when the
        // view letterboxes to the aspect ratio rather than stretching.
        func size(_ value: Double) -> Double { value / width }

        return RoomMapViewState.Drawing(
            aspectRatio: width / height,
            floors: layout.floors.enumerated().map { index, floor in
                .init(id: index, points: floor.map { point($0.x, $0.y) })
            },
            walls: layout.walls.enumerated().map { index, wall in
                .init(
                    id: index,
                    from: point(wall.x1, wall.y1),
                    to: point(wall.x2, wall.y2),
                    thickness: size(wall.drawnThickness)
                )
            },
            doors: layout.doors.enumerated().map { index, door in
                .init(
                    id: index,
                    centre: point(door.x, door.y),
                    width: size(door.drawnWidth),
                    angle: door.angle
                )
            },
            furniture: layout.furniture.enumerated().map { index, piece in
                .init(
                    id: index,
                    label: piece.label?.trimmed.nilIfEmpty,
                    origin: point(piece.x, piece.y),
                    width: size(piece.width),
                    height: size(piece.height)
                )
            },
            // Sorted by id so the drawing is stable between reads: a
            // dictionary hands its values back in no particular order, and an
            // unstable list makes SwiftUI rebuild every token on each reload.
            boxes: layout.boxes.sorted { $0.key < $1.key }.map { id, token in
                .init(
                    id: id,
                    label: boxNames[id] ?? "",
                    centre: point(token.x, token.y),
                    width: size(token.drawnWidth),
                    height: size(token.drawnHeight)
                )
            },
            sizeNote: sizeNote(bounds: bounds, unit: unit)
        )
    }

    /// "4.2 m × 3.0 m", or the same in feet.
    static func sizeNote(bounds: MapBounds, unit: MeasurementUnit) -> String {
        let metresWide = bounds.width / RoomLayout.unitsPerMetre
        let metresTall = bounds.height / RoomLayout.unitsPerMetre

        switch unit {
        case .metric:
            return String(format: "%.1f m × %.1f m", metresWide, metresTall)
        case .imperial:
            return String(
                format: "%.1f ft × %.1f ft",
                metresWide * Measurements.feetPerMetre,
                metresTall * Measurements.feetPerMetre
            )
        }
    }
}

/// Which measure a person reads distances in.
///
/// Stored per device rather than per account: it follows the phone you are
/// holding, not the household you are in, and the web client keeps its own.
enum MeasurementUnit: String, CaseIterable, Sendable {
    case metric
    case imperial
}

enum Measurements {
    static let feetPerMetre: Double = 3.28084
}
