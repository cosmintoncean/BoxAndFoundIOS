import Foundation
import Supabase

/// The wire mirror of `room_layouts.layout`.
///
/// A parallel tree rather than making the domain types `Codable`, for the same
/// reason every other table has rows of its own: the domain should not carry
/// the document's spelling. The cost here is more visible than elsewhere,
/// because the document is nested — but the keys are the web client's, this is
/// where a change to them belongs, and defaulting every field is what lets a
/// map saved before a feature existed still open.
private struct LayoutDocument: Decodable {
    var boxes: [String: TokenJSON]?
    var walls: [WallJSON]?
    var doors: [DoorJSON]?
    var floors: [[PointJSON]]?
    var furniture: [FurnitureJSON]?

    var domain: RoomLayout {
        RoomLayout(
            boxes: (boxes ?? [:]).mapValues(\.domain),
            walls: (walls ?? []).map(\.domain),
            doors: (doors ?? []).map(\.domain),
            floors: (floors ?? []).map { $0.map(\.domain) },
            furniture: (furniture ?? []).map(\.domain)
        )
    }
}

private struct PointJSON: Decodable {
    var x: Double?
    var y: Double?
    var domain: MapPoint { MapPoint(x: x ?? 0, y: y ?? 0) }
}

private struct WallJSON: Decodable {
    var x1: Double?
    var y1: Double?
    var x2: Double?
    var y2: Double?
    var thickness: Double?

    var domain: MapWall {
        MapWall(x1: x1 ?? 0, y1: y1 ?? 0, x2: x2 ?? 0, y2: y2 ?? 0, thickness: thickness)
    }
}

private struct DoorJSON: Decodable {
    var x: Double?
    var y: Double?
    var angle: Double?
    var w: Double?

    var domain: MapDoor { MapDoor(x: x ?? 0, y: y ?? 0, angle: angle ?? 0, width: w) }
}

private struct FurnitureJSON: Decodable {
    var type: String?
    var label: String?
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?

    var domain: MapFurniture {
        MapFurniture(
            type: type,
            label: label,
            x: x ?? 0,
            y: y ?? 0,
            width: w ?? 0,
            height: h ?? 0
        )
    }
}

private struct TokenJSON: Decodable {
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?

    var domain: BoxToken { BoxToken(x: x ?? 0, y: y ?? 0, width: w, height: h) }
}

private struct LayoutRow: Decodable {
    let room_id: String?
    let layout: LayoutDocument?
}

struct RoomLayoutRepository: RoomLayoutReading {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    func layout(roomID: String) async throws(InventoryFailure) -> RoomLayout? {
        do {
            let rows: [LayoutRow] = try await client
                .from("room_layouts")
                .select("room_id,layout")
                .eq("room_id", value: roomID)
                .limit(1)
                .execute()
                .value
            return rows.first?.layout?.domain
        } catch {
            throw InventoryFailure.from(error)
        }
    }
}
