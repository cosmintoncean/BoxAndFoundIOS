import Foundation

/// The notification feed, stated without naming Supabase.
protocol NotificationsReading: Sendable {
    /// Newest first, expired rows left out. RLS scopes it to the signed-in
    /// user, so there is no user filter — the same reason the web client omits
    /// one.
    func feed(limit: Int) async throws(NotificationFailure) -> [AppNotification]

    /// The badge: unread and not expired.
    func unreadCount() async throws(NotificationFailure) -> Int

    func markRead(id: String) async throws(NotificationFailure)
    func markAllRead() async throws(NotificationFailure)
    func delete(id: String) async throws(NotificationFailure)

    /// Fires whenever a row is inserted for this user. Nothing is carried on
    /// it: a presenter reloads the feed rather than trusting a payload it
    /// would have to merge by hand.
    func changes() -> AsyncStream<Void>

    /// Per-type preferences, and the write that changes one.
    func preferences() async throws(NotificationFailure) -> [String: Bool]
    func setPreference(type: String, enabled: Bool) async throws(NotificationFailure)
}

/// Put-it-back requests.
protocol NudgeManaging: Sendable {
    func availability(itemID: String, now: Date) async throws(NotificationFailure) -> NudgeAvailability

    func send(
        itemID: String,
        boxID: String,
        householdID: String,
        senderID: String,
        recipientID: String,
        itemName: String,
        boxName: String?,
        message: String?
    ) async throws(NotificationFailure)

    /// Nudges pointed at this user that they have not dismissed.
    func pending(recipientID: String, householdID: String) async throws(NotificationFailure) -> [Nudge]

    func dismiss(nudgeID: String) async throws(NotificationFailure)
}
