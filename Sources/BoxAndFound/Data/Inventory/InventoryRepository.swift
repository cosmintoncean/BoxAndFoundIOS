import Foundation
import Supabase

/// Reads the inventory. Every table is RLS-scoped by household membership, so
/// these queries carry no ownership filter beyond the one they read by.
///
/// Network only, deliberately. Android grew a Room cache later; the milestone
/// table keeps the offline copy at M8 here too, because a half-populated cache
/// that looks like an empty household is worse than an error.
struct InventoryRepository: InventoryReading {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    /// Every household this person can see.
    ///
    /// Two queries, because owners are not rows in `household_members` — the
    /// web client has the same split. They run concurrently and are merged by
    /// id, since owning a household you are also a member of would otherwise
    /// list it twice.
    func households(userID: String) async throws(InventoryFailure) -> [Household] {
        try await run {
            async let owned: [HouseholdRow] = client
                .from("households")
                .select()
                .eq("owner_id", value: userID)
                .execute()
                .value

            async let joined: [MembershipRow] = client
                .from("household_members")
                .select("household:households(*)")
                .eq("user_id", value: userID)
                .execute()
                .value

            let all = try await owned.map(\.domain)
                + (try await joined).compactMap { $0.household?.domain }

            var seen = Set<String>()
            return all
                .filter { seen.insert($0.id).inserted }
                .sorted { InventorySort.key($0.name) < InventorySort.key($1.name) }
        }
    }

    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] {
        try await run {
            let rows: [RoomRow] = try await client
                .from("rooms")
                .select()
                .eq("household_id", value: householdID)
                .order("name", ascending: true)
                .execute()
                .value
            return rows.map(\.domain)
        }
    }

    /// Boxes with their items in one round trip, matching the web client's
    /// `*, box_items(...)` projection. Item ordering is applied when `Box` is
    /// built, because PostgREST will not sort an embedded table.
    func boxes(householdID: String) async throws(InventoryFailure) -> [Box] {
        try await run {
            let rows: [BoxRow] = try await client
                .from("boxes")
                .select(Self.boxColumns)
                .eq("household_id", value: householdID)
                .order("name", ascending: true)
                .execute()
                .value
            return rows.map(\.domain)
        }
    }

    /// One box with its items, for the detail screen and the `?box=ID` deep
    /// link at M4.
    func box(id: String) async throws(InventoryFailure) -> Box {
        try await run {
            let row: BoxRow = try await client
                .from("boxes")
                .select(Self.boxColumns)
                .eq("id", value: id)
                .single()
                .execute()
                .value
            return row.domain
        }
    }

    private static let boxColumns =
        "*, box_items(id,name,qty,position,taken,taken_at,taken_by)"

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

extension InventoryFailure {
    /// The one place that knows how PostgREST and URLSession spell failure.
    ///
    /// Idempotent on purpose: a caller that already holds an `InventoryFailure`
    /// can pass it straight back through, which lets every `catch` be an
    /// untyped one and stay correct whether or not typed throws survived
    /// inference at that call site.
    static func from(_ error: Error) -> InventoryFailure {
        if let failure = error as? InventoryFailure { return failure }
        if error is CancellationError { return .network }
        if error is URLError { return .network }
        if let postgrest = error as? PostgrestError {
            // PGRST116 is "no rows returned" for a .single() query — a missing
            // box, not a broken one.
            if postgrest.code == "PGRST116" { return .notFound }
            return .unknown(detail: postgrest.message)
        }
        if error is DecodingError {
            // A schema drift, not a connectivity problem. Worth telling apart
            // in logs even though both end as "something went wrong".
            return .unknown(detail: "Response did not match the expected shape")
        }
        return .unknown(detail: error.localizedDescription)
    }
}
