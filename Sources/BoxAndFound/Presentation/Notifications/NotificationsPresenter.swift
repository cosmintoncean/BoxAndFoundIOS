import Foundation
import Observation

/// Drives the notification feed.
@MainActor
@Observable
final class NotificationsPresenter: Presenter {

    private let notifications: any NotificationsReading

    private var rows: [AppNotification] = []
    private var unread = 0
    private var isLoading = true
    private var failure: NotificationFailure?
    private var watcher: Task<Void, Never>?

    init(notifications: any NotificationsReading = Dependencies.notifications) {
        self.notifications = notifications
    }

    var viewState: NotificationsViewState {
        NotificationsViewState(
            content: content,
            badgeText: NotificationCopy.badge(unread: unread),
            isMarkAllEnabled: unread > 0
        )
    }

    private var content: NotificationsViewState.Content {
        if let failure { return .failed(message: NotificationCopy.message(for: failure)) }
        if isLoading && rows.isEmpty { return .loading }
        if rows.isEmpty { return .empty(message: NotificationCopy.empty) }
        return .rows(
            rows.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    body: $0.body?.trimmed.nilIfEmpty,
                    timeAgo: NotificationCopy.timeAgo(from: $0.createdAt),
                    isUnread: $0.isUnread,
                    symbol: NotificationCopy.symbol(forType: $0.type)
                )
            }
        )
    }

    // MARK: - Intents

    func appeared() async {
        await reload()
        startWatching()
    }

    func refreshed() async {
        await reload()
    }

    /// Closes the subscription. An intent rather than a `deinit`, because
    /// `deinit` is nonisolated and cannot touch main-actor state — and a
    /// socket left open behind a dismissed screen is a real leak.
    func disappeared() {
        watcher?.cancel()
        watcher = nil
    }

    /// Marking read is the whole interaction: there is nowhere to go from a
    /// notification yet, so tapping one acknowledges it.
    func rowTapped(_ id: String) async {
        guard rows.first(where: { $0.id == id })?.isUnread == true else { return }
        await act { try await self.notifications.markRead(id: id) }
    }

    func markAllReadTapped() async {
        guard unread > 0 else { return }
        await act { try await self.notifications.markAllRead() }
    }

    func deleteTapped(_ id: String) async {
        await act { try await self.notifications.delete(id: id) }
    }

    // MARK: -

    /// Idempotent, because SwiftUI may run `task` again after a scene change
    /// and a second subscription would double every reload.
    private func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            guard let self else { return }
            for await _ in self.notifications.changes() {
                await self.reload()
            }
        }
    }

    private func act(_ block: @MainActor () async throws -> Void) async {
        do {
            try await block()
            await reload()
        } catch {
            failure = NotificationFailure.from(error)
        }
    }

    private func reload() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            rows = try await notifications.feed(limit: 30)
            unread = try await notifications.unreadCount()
        } catch {
            failure = NotificationFailure.from(error)
        }
    }
}

/// Drives the per-type preference toggles.
@MainActor
@Observable
final class NotificationSettingsPresenter: Presenter {

    private let notifications: any NotificationsReading

    private var prefs: [String: Bool] = [:]
    private var isLoading = true
    private var failure: NotificationFailure?

    init(notifications: any NotificationsReading = Dependencies.notifications) {
        self.notifications = notifications
    }

    var viewState: NotificationSettingsViewState {
        NotificationSettingsViewState(
            isLoading: isLoading,
            toggles: NotificationType.allCases.map {
                .init(
                    id: $0.rawValue,
                    title: NotificationCopy.title(forType: $0),
                    detail: NotificationCopy.detail(forType: $0),
                    isOn: NotificationPrefs.isEnabled(prefs, type: $0.rawValue)
                )
            },
            notice: failure.map(NotificationCopy.message(for:))
        )
    }

    func appeared() async {
        await reload()
    }

    func toggled(_ type: String, to enabled: Bool) async {
        // Moved locally first so the switch does not spring back while the
        // write is in flight; a failure reloads and puts it where it belongs.
        prefs = NotificationPrefs.setting(prefs, type: type, enabled: enabled)
        failure = nil
        do {
            try await notifications.setPreference(type: type, enabled: enabled)
        } catch {
            failure = NotificationFailure.from(error)
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            prefs = try await notifications.preferences()
        } catch {
            failure = NotificationFailure.from(error)
        }
    }
}
