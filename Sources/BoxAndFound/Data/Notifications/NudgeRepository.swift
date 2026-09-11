import Foundation
import Supabase

private struct NudgeRow: Decodable {
    let id: String
    let item_id: String
    let box_id: String
    let sender_id: String?
    let item_name: String
    let box_name: String?
    let message: String?
    let created_at: String

    var domain: Nudge {
        Nudge(
            id: id,
            itemID: item_id,
            boxID: box_id,
            senderID: sender_id,
            itemName: item_name,
            boxName: box_name,
            message: message,
            createdAt: created_at
        )
    }
}

private struct NudgeTimestampRow: Decodable {
    let created_at: String
}

struct NudgeRepository: NudgeManaging {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    private static let columns = "id,item_id,box_id,sender_id,item_name,box_name,message,created_at"

    /// Whether this user may nudge this item right now.
    ///
    /// `last_recent_nudge` only returns a row if *this* sender nudged *this*
    /// item inside the window. Asking the server rather than remembering
    /// locally is deliberate: the cooldown is per sender-and-item and has to
    /// hold across devices and across all three clients.
    func availability(
        itemID: String,
        now: Date = Date()
    ) async throws(NotificationFailure) -> NudgeAvailability {
        try await run {
            let params: [String: AnyJSON] = ["p_item_id": .string(itemID)]
            let rows: [NudgeTimestampRow] = try await client
                .rpc("last_recent_nudge", params: params)
                .execute()
                .value
            let lastSentAt = rows.first.flatMap { Premium.parseTimestamp($0.created_at) }
            return NudgeCooldown.availability(lastSentAt: lastSentAt, now: now)
        }
    }

    /// Item and box names are snapshotted onto the row, as the web client
    /// does, so the message still reads correctly after the item is renamed or
    /// deleted.
    func send(
        itemID: String,
        boxID: String,
        householdID: String,
        senderID: String,
        recipientID: String,
        itemName: String,
        boxName: String?,
        message: String?
    ) async throws(NotificationFailure) {
        try await run {
            let body: [String: AnyJSON] = [
                "item_id": .string(itemID),
                "box_id": .string(boxID),
                "household_id": .string(householdID),
                "sender_id": .string(senderID),
                "recipient_id": .string(recipientID),
                "item_name": .string(itemName),
                "box_name": boxName.map { AnyJSON.string($0) } ?? .null,
                "message": message?.trimmed.nilIfEmpty.map { AnyJSON.string($0) } ?? .null,
            ]
            _ = try await client.from("item_nudges").insert(body).execute()
        }
    }

    func pending(
        recipientID: String,
        householdID: String
    ) async throws(NotificationFailure) -> [Nudge] {
        try await run {
            let rows: [NudgeRow] = try await client
                .from("item_nudges")
                .select(Self.columns)
                .eq("recipient_id", value: recipientID)
                .eq("household_id", value: householdID)
                .is("dismissed_at", value: nil)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
            return rows.map(\.domain)
        }
    }

    func dismiss(nudgeID: String) async throws(NotificationFailure) {
        try await run {
            let body: [String: AnyJSON] = ["dismissed_at": .string(ItemSync.timestamp())]
            _ = try await client
                .from("item_nudges")
                .update(body)
                .eq("id", value: nudgeID)
                .execute()
        }
    }

    private func run<T>(
        _ block: () async throws -> T
    ) async throws(NotificationFailure) -> T {
        do {
            return try await block()
        } catch {
            throw NotificationFailure.from(error)
        }
    }
}
