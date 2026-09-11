#if DEBUG
import Foundation

/// A notification feed and nudge store in memory, for the UI tests.
///
/// `@unchecked Sendable` for the same reason `FixtureInventory` is: the
/// protocols require it, the state is plain, and every caller is a main-actor
/// presenter.
final class FixtureNotifications: NotificationsReading, NudgeManaging, @unchecked Sendable {

    private var rows: [AppNotification] = [
        AppNotification(
            id: "n1",
            type: NotificationType.nudgeRequest.rawValue,
            title: "Cosmin wants the Scarf back",
            body: "From Winter Clothes",
            link: nil,
            readAt: nil,
            createdAt: ItemSync.timestamp(),
            expiresAt: nil
        ),
        AppNotification(
            id: "n2",
            type: NotificationType.memberJoined.rawValue,
            title: "Sam joined Home",
            body: nil,
            link: nil,
            // Read already, so the list has one of each and the unread count
            // is something other than "all of them".
            readAt: ItemSync.timestamp(),
            createdAt: ItemSync.timestamp(),
            expiresAt: nil
        ),
    ]

    private var prefs: [String: Bool] = [:]
    private var nudges: [Nudge] = []

    // MARK: - Feed

    func feed(limit: Int) async throws(NotificationFailure) -> [AppNotification] {
        Array(rows.prefix(limit))
    }

    func unreadCount() async throws(NotificationFailure) -> Int {
        rows.filter(\.isUnread).count
    }

    func markRead(id: String) async throws(NotificationFailure) {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].isUnread else { return }
        rows[index] = marked(rows[index], readAt: ItemSync.timestamp())
    }

    func markAllRead() async throws(NotificationFailure) {
        rows = rows.map { $0.isUnread ? marked($0, readAt: ItemSync.timestamp()) : $0 }
    }

    func delete(id: String) async throws(NotificationFailure) {
        rows.removeAll { $0.id == id }
    }

    /// Never fires. A fixture socket would only make the tests flaky; what the
    /// suite checks is that the feed loads, marks and deletes.
    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    // MARK: - Preferences

    func preferences() async throws(NotificationFailure) -> [String: Bool] { prefs }

    func setPreference(type: String, enabled: Bool) async throws(NotificationFailure) {
        prefs = NotificationPrefs.setting(prefs, type: type, enabled: enabled)
    }

    // MARK: - Nudges

    func availability(
        itemID: String,
        now: Date
    ) async throws(NotificationFailure) -> NudgeAvailability {
        let last = nudges.first { $0.itemID == itemID }
            .flatMap { Premium.parseTimestamp($0.createdAt) }
        return NudgeCooldown.availability(lastSentAt: last, now: now)
    }

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
        nudges.insert(
            Nudge(
                id: UUID().uuidString,
                itemID: itemID,
                boxID: boxID,
                senderID: senderID,
                itemName: itemName,
                boxName: boxName,
                message: message,
                createdAt: ItemSync.timestamp()
            ),
            at: 0
        )
    }

    func pending(
        recipientID: String,
        householdID: String
    ) async throws(NotificationFailure) -> [Nudge] {
        nudges
    }

    func dismiss(nudgeID: String) async throws(NotificationFailure) {
        nudges.removeAll { $0.id == nudgeID }
    }

    // MARK: -

    private func marked(_ row: AppNotification, readAt: String) -> AppNotification {
        AppNotification(
            id: row.id,
            type: row.type,
            title: row.title,
            body: row.body,
            link: row.link,
            readAt: readAt,
            createdAt: row.createdAt,
            expiresAt: row.expiresAt
        )
    }
}
#endif
