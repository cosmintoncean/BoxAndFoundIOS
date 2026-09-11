import Foundation

/// A row from `notifications`.
///
/// Producers run server-side with the service-role key, so a client only ever
/// reads and marks its own — it never inserts one.
struct AppNotification: Equatable, Identifiable, Sendable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let readAt: String?
    let createdAt: String
    let expiresAt: String?

    var isUnread: Bool { readAt == nil }
}

/// The types the server produces today. A closed list so a preferences screen
/// can name them; a type added server-side simply is not listed here yet, and
/// `NotificationPrefs` leaves it enabled until someone opts out.
enum NotificationType: String, CaseIterable, Sendable {
    case memberJoined = "member_joined"
    case nudgeRequest = "nudge_request"
    case premiumExpiring = "premium_expiring"
}

/// A put-it-back request, from `item_nudges`.
struct Nudge: Equatable, Identifiable, Sendable {
    let id: String
    let itemID: String
    let boxID: String
    let senderID: String?
    /// Snapshotted on the row by whoever sent it, as the web client does, so
    /// the message still reads correctly after the item is renamed or deleted.
    let itemName: String
    let boxName: String?
    let message: String?
    let createdAt: String
}

/// Whether a nudge can be sent, and if not, how long is left.
enum NudgeAvailability: Equatable, Sendable {
    case available
    case onCooldown(remaining: TimeInterval)
}

/// The 24-hour rule, as arithmetic.
///
/// The window itself is enforced by `last_recent_nudge` server-side, because
/// the cooldown is per sender-and-item and has to hold across devices and
/// across all three clients. This turns the row it returns into an answer, and
/// is pure so the boundaries can be tested without a clock.
enum NudgeCooldown {
    static let duration: TimeInterval = 24 * 60 * 60

    static func availability(lastSentAt: Date?, now: Date) -> NudgeAvailability {
        guard let lastSentAt else { return .available }
        let remaining = duration - now.timeIntervalSince(lastSentAt)
        // A clock that has gone backwards, or a row from the future, should not
        // lock someone out for longer than the window itself.
        guard remaining > 0 else { return .available }
        return .onCooldown(remaining: min(remaining, duration))
    }
}

/// Why a notification or nudge operation did not happen.
enum NotificationFailure: Error, Equatable, Sendable {
    case network
    case unknown(detail: String?)
}
