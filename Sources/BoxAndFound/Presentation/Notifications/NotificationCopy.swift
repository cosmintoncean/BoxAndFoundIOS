import Foundation

/// Where notifications become words and pictures.
enum NotificationCopy {

    static let empty = "Nothing yet. Anything that needs you will turn up here."
    static let nudgeSent = "Asked. They will see it next time they open the app."

    static func message(for failure: NotificationFailure) -> String {
        switch failure {
        case .network: "No connection. Check your network and try again."
        case .unknown: "Something went wrong. Try again."
        }
    }

    /// A symbol per type, falling back for a type the server added after this
    /// client shipped. Unknown must still draw something.
    static func symbol(forType type: String) -> String {
        switch NotificationType(rawValue: type) {
        case .memberJoined: "person.badge.plus"
        case .nudgeRequest: "hand.wave"
        case .premiumExpiring: "clock.badge.exclamationmark"
        case nil: "bell"
        }
    }

    static func title(forType type: NotificationType) -> String {
        switch type {
        case .memberJoined: "Someone joins a household"
        case .nudgeRequest: "Someone asks for an item back"
        case .premiumExpiring: "Premium is about to expire"
        }
    }

    static func detail(forType type: NotificationType) -> String {
        switch type {
        case .memberJoined: "When a person accepts an invite to a household you are in."
        case .nudgeRequest: "When someone wants an item you took put back."
        case .premiumExpiring: "A reminder a few days before it lapses."
        }
    }

    /// Nil when nothing is unread: an absent badge reads better than a zero.
    /// Capped, because a three-digit badge is a smear rather than a number.
    static func badge(unread: Int) -> String? {
        switch unread {
        case ..<1: nil
        case 100...: "99+"
        default: "\(unread)"
        }
    }

    /// "just now", "2 hours ago", "3 days ago".
    ///
    /// Takes `now` so the wording can be tested at a fixed instant rather than
    /// whenever the suite happens to run.
    static func timeAgo(from timestamp: String, now: Date = Date()) -> String {
        guard let date = Premium.parseTimestamp(timestamp) else { return "" }
        let elapsed = now.timeIntervalSince(date)
        // Under a minute, and anything from a clock that has run ahead, reads
        // as now — "in 3 seconds" on a notification is nonsense.
        guard elapsed >= 60 else { return "just now" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Where asking for something back becomes words.
enum NudgeCopy {

    static func sheetTitle(_ itemName: String) -> String {
        "Ask for \(itemName) back?"
    }

    /// Nil when the window is clear. Rounded up to the next whole unit,
    /// because "in 0 hours" is not an answer and a countdown that ticks to
    /// zero on screen invites a tap that will fail.
    static func cooldownNote(_ availability: NudgeAvailability) -> String? {
        guard case .onCooldown(let remaining) = availability else { return nil }
        let hours = Int((remaining / 3600).rounded(.up))
        if hours > 1 {
            return "You asked recently. You can ask again in about \(hours) hours."
        }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        return minutes > 1
            ? "You asked recently. You can ask again in about \(minutes) minutes."
            : "You asked recently. You can ask again in about a minute."
    }

    /// "Cosmin asked for the Scarf back", or the item alone when the sender is
    /// not known — the row keeps a sender id, not a name.
    static func pendingNote(itemName: String, message: String?) -> String {
        let base = "Someone asked for \(itemName) back"
        guard let message = message?.trimmed.nilIfEmpty else { return base + "." }
        return base + ": \(message)"
    }
}
