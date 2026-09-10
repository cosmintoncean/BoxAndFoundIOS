import Foundation

/// An item as the editor holds it: `id` is nil until the row exists.
struct DraftItem: Equatable, Sendable {
    var id: String?
    var name: String
    var quantity: Int = 1
    var isTaken: Bool = false
    var takenAt: String?
    var takenBy: String?
}

/// A row to create. Position is assigned by the diff, not by the caller.
struct ItemInsert: Equatable, Sendable {
    let name: String
    let quantity: Int
    let position: Int
    let isTaken: Bool
    let takenAt: String?
    let takenBy: String?
}

/// A field in a patch. Absent means "leave it alone"; `.set(nil)` means
/// "clear it". `String??` says the same thing but reads like a typo.
enum FieldChange<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case set(Value?)
}

/// Only the fields that actually changed, so two editors do not fight over
/// the rest.
struct ItemUpdate: Equatable, Sendable {
    /// `taken`, `taken_at` and `taken_by` always move together. A returned
    /// item still holding a stale `taken_by` would misattribute the nudges
    /// that read it, so they are one change rather than three.
    struct TakenChange: Equatable, Sendable {
        let isTaken: Bool
        let at: String?
        let by: String?
    }

    let id: String
    var name: String?
    var quantity: Int?
    var position: Int?
    var taken: TakenChange?

    var isEmpty: Bool {
        name == nil && quantity == nil && position == nil && taken == nil
    }
}

struct ItemSyncPlan: Equatable, Sendable {
    var inserts: [ItemInsert] = []
    var updates: [ItemUpdate] = []
    var deletes: [String] = []

    var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// Works out the minimal set of writes to turn `existing` into `desired`.
///
/// This deliberately replaces the web client's `syncBoxItems`, which deletes
/// every `box_items` row for a box and reinserts the lot. That has two real
/// consequences:
///
/// - Item ids change on every save, so `item_nudges.item_id` references go
///   stale and the 24-hour nudge cooldown silently stops working.
/// - Two household members saving the same box clobber each other: the second
///   save deletes rows the first just created, rather than merging.
///
/// Diffing by id fixes both. An item the editor never touched is not written
/// at all, so a concurrent edit to a different item survives. Ported from the
/// Android client, where the same thirteen behaviours are pinned by tests.
enum ItemSync {

    static func plan(
        existing: [BoxItem],
        desired: [DraftItem],
        currentUserID: String?,
        now: () -> String = timestamp
    ) -> ItemSyncPlan {
        // An item whose name was blanked is a deletion, not an empty row.
        let named = desired.filter { !$0.name.trimmed.isEmpty }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        var plan = ItemSyncPlan()

        for (index, draft) in named.enumerated() {
            let name = draft.name.trimmed
            // A quantity below one is a typo, not an instruction to remove.
            let quantity = max(draft.quantity, 1)

            guard let id = draft.id, let current = existingByID[id] else {
                plan.inserts.append(
                    ItemInsert(
                        name: name,
                        quantity: quantity,
                        position: index,
                        isTaken: draft.isTaken,
                        takenAt: draft.isTaken ? (draft.takenAt ?? now()) : nil,
                        takenBy: draft.isTaken ? (draft.takenBy ?? currentUserID) : nil
                    )
                )
                continue
            }

            var update = ItemUpdate(id: current.id)
            if name != current.name { update.name = name }
            if quantity != current.quantity { update.quantity = quantity }
            if index != current.position { update.position = index }
            if draft.isTaken != current.isTaken {
                update.taken = ItemUpdate.TakenChange(
                    isTaken: draft.isTaken,
                    at: draft.isTaken ? now() : nil,
                    by: draft.isTaken ? currentUserID : nil
                )
            }
            if !update.isEmpty { plan.updates.append(update) }
        }

        // Anything that had a row and is no longer in the list.
        let kept = Set(named.compactMap(\.id))
        plan.deletes = existing.map(\.id).filter { !kept.contains($0) }

        return plan
    }

    /// The position a newly added item should take at the end of a list.
    static func nextPosition(after existing: [BoxItem]) -> Int {
        (existing.map(\.position).max() ?? -1) + 1
    }

    /// What the server stores in `taken_at`. Matches the web client's
    /// `new Date().toISOString()`.
    static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
