import Foundation
import Supabase

/// Wire shapes for the two Postgres functions and the households table.
private struct InvitePreviewRow: Decodable {
    let household_id: String
    let household_name: String?
    let owner_name: String?
    let member_count: Int?
    let already_member: Bool?

    var domain: InvitePreview {
        InvitePreview(
            householdID: household_id,
            householdName: household_name,
            ownerName: owner_name,
            memberCount: member_count ?? 0,
            isAlreadyMember: already_member ?? false
        )
    }
}

private struct HouseholdMemberRow: Decodable {
    let user_id: String
    let display_name: String?
    let email: String?

    var domain: HouseholdMember {
        HouseholdMember(userID: user_id, displayName: display_name, email: email)
    }
}

struct HouseholdRepository: HouseholdManaging {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    /// The invite code is generated client-side in the same shape the web
    /// client uses — six upper-case base-36 characters — so a code read out
    /// over the phone works on any client.
    func create(name: String, ownerID: String) async throws(HouseholdFailure) -> Household {
        try await run {
            let body: [String: AnyJSON] = [
                "name": .string(name.trimmed),
                "invite_code": .string(InviteCode.random()),
                "owner_id": .string(ownerID),
            ]
            let row: HouseholdRow = try await client
                .from("households")
                .insert(body)
                .select()
                .single()
                .execute()
                .value
            return row.domain
        }
    }

    func rename(householdID: String, name: String) async throws(HouseholdFailure) {
        try await run {
            let body: [String: AnyJSON] = ["name": .string(name.trimmed)]
            _ = try await client
                .from("households")
                .update(body)
                .eq("id", value: householdID)
                .execute()
        }
    }

    func regenerateInviteCode(householdID: String) async throws(HouseholdFailure) -> String {
        try await run {
            let code = InviteCode.random()
            let body: [String: AnyJSON] = ["invite_code": .string(code)]
            _ = try await client
                .from("households")
                .update(body)
                .eq("id", value: householdID)
                .execute()
            return code
        }
    }

    func previewInvite(code: String) async throws(HouseholdFailure) -> InvitePreview {
        let rows: [InvitePreviewRow] = try await run {
            let params: [String: AnyJSON] = ["code": .string(InviteCode.normalise(code))]
            return try await client
                .rpc("get_invite_preview", params: params)
                .execute()
                .value
        }
        // The function returns a set, and an unknown code returns an empty one
        // rather than an error. That is a real answer, not a failure to reach
        // the server, so it gets its own case.
        guard let first = rows.first else { throw HouseholdFailure.unknownInviteCode }
        return first.domain
    }

    /// A duplicate is success: two taps on Accept, or joining a household you
    /// are already in, should land you inside rather than showing an error.
    /// The web client special-cases the same thing.
    func join(householdID: String, userID: String) async throws(HouseholdFailure) {
        do {
            let body: [String: AnyJSON] = [
                "household_id": .string(householdID),
                "user_id": .string(userID),
            ]
            _ = try await client.from("household_members").insert(body).execute()
        } catch let error as PostgrestError where Self.isDuplicate(error) {
            return
        } catch {
            throw HouseholdFailure.from(error)
        }
    }

    func leave(householdID: String, userID: String) async throws(HouseholdFailure) {
        try await run {
            _ = try await client
                .from("household_members")
                .delete()
                .eq("household_id", value: householdID)
                .eq("user_id", value: userID)
                .execute()
        }
    }

    func members(householdID: String) async throws(HouseholdFailure) -> [HouseholdMember] {
        try await run {
            let rows: [HouseholdMemberRow] = try await client
                .rpc("get_household_members", params: ["hh_id": AnyJSON.string(householdID)])
                .execute()
                .value
            return rows.map(\.domain)
        }
    }

    /// Deliberately an RPC rather than the web client's six sequential
    /// deletes. See `HouseholdFailure.deleteFunctionMissing` for why a missing
    /// function is an error here rather than a fallback.
    func delete(householdID: String) async throws(HouseholdFailure) {
        do {
            let params: [String: AnyJSON] = ["hh_id": .string(householdID)]
            _ = try await client.rpc("delete_household", params: params).execute()
        } catch let error as PostgrestError where Self.isMissingFunction(error) {
            throw HouseholdFailure.deleteFunctionMissing
        } catch {
            throw HouseholdFailure.from(error)
        }
    }

    // MARK: -

    /// 23505 is Postgres' unique-violation code; PostgREST passes it through.
    private static func isDuplicate(_ error: PostgrestError) -> Bool {
        error.code == "23505" || error.message.lowercased().contains("duplicate")
    }

    /// PGRST202 is "no function matching that name and signature".
    private static func isMissingFunction(_ error: PostgrestError) -> Bool {
        error.code == "PGRST202" || error.message.lowercased().contains("could not find the function")
    }

    private func run<T>(
        _ block: () async throws -> T
    ) async throws(HouseholdFailure) -> T {
        do {
            return try await block()
        } catch {
            throw HouseholdFailure.from(error)
        }
    }
}

extension HouseholdFailure {
    /// Idempotent, for the same reason `InventoryFailure.from` is: every catch
    /// can stay untyped and remain correct however inference lands.
    static func from(_ error: Error) -> HouseholdFailure {
        if let failure = error as? HouseholdFailure { return failure }
        if error is CancellationError { return .network }
        if error is URLError { return .network }
        if let postgrest = error as? PostgrestError {
            return .unknown(detail: postgrest.message)
        }
        if error is DecodingError {
            return .unknown(detail: "Response did not match the expected shape")
        }
        return .unknown(detail: error.localizedDescription)
    }
}
