import Foundation
import Supabase

private struct NotificationRow: Decodable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let read_at: String?
    let created_at: String
    let expires_at: String?

    var domain: AppNotification {
        AppNotification(
            id: id,
            type: type,
            title: title,
            body: body,
            link: link,
            readAt: read_at,
            createdAt: created_at,
            expiresAt: expires_at
        )
    }
}

struct NotificationRepository: NotificationsReading {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    private static let columns = "id,type,title,body,link,read_at,created_at,expires_at"

    func feed(limit: Int = 30) async throws(NotificationFailure) -> [AppNotification] {
        try await run {
            let rows: [NotificationRow] = try await client
                .from("notifications")
                .select(Self.columns)
                // Expiry is filtered in the query rather than after it, so a
                // limit of thirty is thirty live rows and not thirty rows of
                // which some are already gone.
                .or("expires_at.is.null,expires_at.gt.\(Self.now())")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows.map(\.domain)
        }
    }

    /// Counted by the server rather than by fetching the rows and measuring
    /// the array: this is a badge, and someone who has not opened the app in a
    /// month should not pay for every row to come down the wire to produce one
    /// number.
    func unreadCount() async throws(NotificationFailure) -> Int {
        try await run {
            let response = try await client
                .from("notifications")
                .select("id", head: true, count: .exact)
                .is("read_at", value: nil)
                .or("expires_at.is.null,expires_at.gt.\(Self.now())")
                .execute()
            return response.count ?? 0
        }
    }

    /// Idempotent: the `read_at is null` guard makes re-marking a no-op, so
    /// tapping a notification twice does not rewrite the timestamp.
    func markRead(id: String) async throws(NotificationFailure) {
        try await run {
            let body: [String: AnyJSON] = ["read_at": .string(Self.now())]
            _ = try await client
                .from("notifications")
                .update(body)
                .eq("id", value: id)
                .is("read_at", value: nil)
                .execute()
        }
    }

    func markAllRead() async throws(NotificationFailure) {
        try await run {
            let body: [String: AnyJSON] = ["read_at": .string(Self.now())]
            _ = try await client
                .from("notifications")
                .update(body)
                .is("read_at", value: nil)
                .execute()
        }
    }

    func delete(id: String) async throws(NotificationFailure) {
        try await run {
            _ = try await client.from("notifications").delete().eq("id", value: id).execute()
        }
    }

    /// A tick per insert, with nothing on it.
    ///
    /// The payload is deliberately ignored: merging a raw row into a feed that
    /// is already filtered by expiry and ordered by date would duplicate the
    /// query's rules in a second place. RLS scopes the stream to this user, so
    /// a tick means "something of yours arrived" and the presenter re-reads.
    func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                // `client.realtime` is still the v1 client; `client.channel`
                // is the v2 one, and only v2 speaks postgres changes.
                let channel = client.channel("notifications-feed")
                let inserts = channel.postgresChange(InsertAction.self, table: "notifications")
                await channel.subscribe()
                for await _ in inserts {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Preferences

    func preferences() async throws(NotificationFailure) -> [String: Bool] {
        try await run {
            let metadata = client.auth.currentUser?.userMetadata ?? [:]
            guard let stored = metadata["notif_prefs"]?.objectValue else { return [:] }
            // Only real booleans survive. A null means "no opinion", which is
            // the same as absent, and absent means enabled.
            return stored.compactMapValues(\.boolValue)
        }
    }

    func setPreference(type: String, enabled: Bool) async throws(NotificationFailure) {
        let current = try await preferences()
        let merged = NotificationPrefs.setting(current, type: type, enabled: enabled)
        try await run {
            // The whole object is written, as the other clients do: sending
            // one key would drop a preference set on another device.
            let object = merged.mapValues { AnyJSON.bool($0) }
            _ = try await client.auth.update(user: UserAttributes(data: ["notif_prefs": .object(object)]))
        }
    }

    // MARK: -

    private static func now() -> String {
        ItemSync.timestamp()
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

extension NotificationFailure {
    static func from(_ error: Error) -> NotificationFailure {
        if let failure = error as? NotificationFailure { return failure }
        if error is CancellationError { return .network }
        if error is URLError { return .network }
        if let postgrest = error as? PostgrestError { return .unknown(detail: postgrest.message) }
        if error is DecodingError {
            return .unknown(detail: "Response did not match the expected shape")
        }
        return .unknown(detail: error.localizedDescription)
    }
}
