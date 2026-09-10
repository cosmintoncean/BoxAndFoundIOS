import Foundation
import Supabase

/// Every write the inventory makes.
struct InventoryWriteRepository: InventoryWriting {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    // MARK: - Rooms

    func createRoom(householdID: String, name: String) async throws(InventoryFailure) -> Room {
        try await run {
            // Annotated rather than inline: `insert` takes `some Encodable`,
            // which gives the literal nothing to infer `AnyJSON` from.
            let body: [String: AnyJSON] = [
                "name": .string(name.trimmed),
                "household_id": .string(householdID),
            ]
            let row: RoomRow = try await client
                .from("rooms")
                .insert(body)
                .select()
                .single()
                .execute()
                .value
            return row.domain
        }
    }

    /// `boxes.room_id` is nullable and has no cascade, so boxes in a deleted
    /// room simply become unassigned. The list already shows those under
    /// "No room".
    func deleteRoom(id: String) async throws(InventoryFailure) {
        try await run {
            _ = try await client.from("rooms").delete().eq("id", value: id).execute()
        }
    }

    // MARK: - Boxes

    func createBox(
        householdID: String,
        name: String,
        icon: String,
        location: String?,
        roomID: String?,
        imageURL: String?
    ) async throws(InventoryFailure) -> Box {
        try await run {
            let body: [String: AnyJSON] = [
                "household_id": .string(householdID),
                "name": .string(name.trimmed),
                "icon": .string(BoxIcons.normalise(icon)),
                "location": json(location?.trimmed.nilIfEmpty),
                "room_id": json(roomID),
                "image_url": json(imageURL),
            ]
            let row: BoxRow = try await client
                .from("boxes")
                .insert(body)
                .select(Self.boxColumns)
                .single()
                .execute()
                .value
            return row.domain
        }
    }

    /// Only the fields the editor changed are sent, so saving a box does not
    /// overwrite a field another member edited in the meantime.
    func updateBox(id: String, changes: BoxChanges) async throws(InventoryFailure) {
        guard !changes.isEmpty else { return }
        try await run {
            var body: [String: AnyJSON] = [:]
            put(&body, "name", changes.name)
            put(&body, "icon", changes.icon)
            put(&body, "location", changes.location)
            put(&body, "room_id", changes.roomID)
            put(&body, "image_url", changes.imageURL)
            _ = try await client.from("boxes").update(body).eq("id", value: id).execute()
        }
    }

    /// `box_items` cascades from `boxes`, so the items go with it.
    func deleteBox(id: String) async throws(InventoryFailure) {
        try await run {
            _ = try await client.from("boxes").delete().eq("id", value: id).execute()
        }
    }

    // MARK: - Items

    /// Applies an `ItemSyncPlan` as the minimal set of writes.
    ///
    /// Not a transaction — PostgREST has no client-side transactions. The
    /// ordering is chosen so a partial failure degrades safely: updates and
    /// inserts first, so an interrupted run leaves duplicates visible rather
    /// than silently losing items. Making it atomic needs a Postgres function,
    /// worth doing when household deletion moves server-side.
    func applyItemPlan(boxID: String, plan: ItemSyncPlan) async throws(InventoryFailure) {
        guard !plan.isEmpty else { return }
        try await run {
            for update in plan.updates {
                var body: [String: AnyJSON] = [:]
                if let name = update.name { body["name"] = .string(name) }
                if let quantity = update.quantity { body["qty"] = .integer(quantity) }
                if let position = update.position { body["position"] = .integer(position) }
                if let taken = update.taken {
                    body["taken"] = .bool(taken.isTaken)
                    body["taken_at"] = json(taken.at)
                    body["taken_by"] = json(taken.by)
                }
                _ = try await client
                    .from("box_items")
                    .update(body)
                    .eq("id", value: update.id)
                    .execute()
            }

            if !plan.inserts.isEmpty {
                let rows: [[String: AnyJSON]] = plan.inserts.map { insert in
                    [
                        "box_id": .string(boxID),
                        "name": .string(insert.name),
                        "qty": .integer(insert.quantity),
                        "position": .integer(insert.position),
                        "taken": .bool(insert.isTaken),
                        "taken_at": json(insert.takenAt),
                        "taken_by": json(insert.takenBy),
                    ]
                }
                _ = try await client.from("box_items").insert(rows).execute()
            }

            if !plan.deletes.isEmpty {
                _ = try await client
                    .from("box_items")
                    .delete()
                    .in("id", values: plan.deletes)
                    .execute()
            }
        }
    }

    /// The taken/returned toggle. `taken_at` and `taken_by` move with `taken`,
    /// because a returned item holding a stale `taken_by` would misattribute
    /// the nudges that read it.
    func setItemTaken(
        itemID: String,
        isTaken: Bool,
        userID: String?
    ) async throws(InventoryFailure) {
        try await run {
            let body: [String: AnyJSON] = [
                "taken": .bool(isTaken),
                "taken_at": json(isTaken ? ItemSync.timestamp() : nil),
                "taken_by": json(isTaken ? userID : nil),
            ]
            _ = try await client
                .from("box_items")
                .update(body)
                .eq("id", value: itemID)
                .execute()
        }
    }

    /// Moves one item to another box.
    ///
    /// The row keeps its id, so a nudge already pointing at this item still
    /// resolves. The web client instead rewrites both boxes wholesale through
    /// `syncBoxItems`, which loses the id and, with it, the nudge.
    func moveItem(itemID: String, toBoxID: String, position: Int) async throws(InventoryFailure) {
        try await run {
            let body: [String: AnyJSON] = [
                "box_id": .string(toBoxID),
                "position": .integer(position),
            ]
            _ = try await client
                .from("box_items")
                .update(body)
                .eq("id", value: itemID)
                .execute()
        }
    }

    // MARK: - Photos

    /// Uploads to the private `box-images` bucket and returns the object path,
    /// which is what `boxes.image_url` stores now that the bucket is closed. A
    /// URL cannot be stored: reading needs one signed for the current session,
    /// and it expires. See `BoxImageURLs` for the read side.
    ///
    /// The path keeps the web client's convention,
    /// `<householdID>/<epochMillis>.<ext>`, which the storage policies depend
    /// on: the first folder segment is the household, and uploading outside
    /// your own is refused.
    func uploadBoxPhoto(
        householdID: String,
        data: Data,
        fileExtension: String
    ) async throws(InventoryFailure) -> String {
        try await run {
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let path = "\(householdID)/\(stamp).\(Self.safeExtension(fileExtension))"
            // FileOptions defaults to upsert: false and infers the content
            // type from the extension, which is what the web client relies on.
            _ = try await client.storage
                .from(AppConfig.storageBucket)
                .upload(path, data: data, options: FileOptions())
            return path
        }
    }

    static func safeExtension(_ raw: String) -> String {
        let cleaned = raw.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .filter(\.isLetter)
        return cleaned.isEmpty ? "jpg" : cleaned
    }

    // MARK: -

    private static let boxColumns =
        "*, box_items(id,name,qty,position,taken,taken_at,taken_by)"

    private func json(_ value: String?) -> AnyJSON {
        value.map { AnyJSON.string($0) } ?? .null
    }

    private func put(_ body: inout [String: AnyJSON], _ column: String, _ change: FieldChange<String>) {
        guard case .set(let value) = change else { return }
        body[column] = json(value)
    }

    private func run<T>(
        _ block: () async throws -> T
    ) async throws(InventoryFailure) -> T {
        do {
            return try await block()
        } catch {
            throw InventoryFailure.from(error)
        }
    }
}
