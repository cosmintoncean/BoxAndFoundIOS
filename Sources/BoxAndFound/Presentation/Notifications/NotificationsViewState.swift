import Foundation

/// Everything the notification feed draws.
struct NotificationsViewState: Equatable {

    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let body: String?
        /// "2 hours ago", already worded.
        let timeAgo: String
        let isUnread: Bool
        /// An SF Symbol chosen from the type. The type itself stops here.
        let symbol: String
    }

    enum Content: Equatable {
        case loading
        case empty(message: String)
        case failed(message: String)
        case rows([Row])
    }

    var content: Content
    /// Nil when there is nothing unread — an absent badge reads better than a
    /// zero.
    var badgeText: String?
    var isMarkAllEnabled: Bool
}

/// Everything the notification settings screen draws.
struct NotificationSettingsViewState: Equatable {

    struct Toggle: Equatable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let isOn: Bool
    }

    var isLoading: Bool
    var toggles: [Toggle]
    var notice: String?
}
