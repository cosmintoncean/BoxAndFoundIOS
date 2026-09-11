import Foundation
import Testing
@testable import BoxAndFound

private final class StubNotifications: NotificationsReading, @unchecked Sendable {
    var rows: [AppNotification] = []
    var prefs: [String: Bool] = [:]
    var failure: NotificationFailure?

    var markedRead: [String] = []
    var markAllCount = 0
    var deleted: [String] = []
    var written: [(type: String, enabled: Bool)] = []

    func feed(limit: Int) async throws(NotificationFailure) -> [AppNotification] {
        if let failure { throw failure }
        return rows
    }

    func unreadCount() async throws(NotificationFailure) -> Int {
        if let failure { throw failure }
        return rows.filter(\.isUnread).count
    }

    func markRead(id: String) async throws(NotificationFailure) {
        if let failure { throw failure }
        markedRead.append(id)
        rows = rows.map { $0.id == id ? read($0) : $0 }
    }

    func markAllRead() async throws(NotificationFailure) {
        if let failure { throw failure }
        markAllCount += 1
        rows = rows.map(read)
    }

    func delete(id: String) async throws(NotificationFailure) {
        if let failure { throw failure }
        deleted.append(id)
        rows.removeAll { $0.id == id }
    }

    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func preferences() async throws(NotificationFailure) -> [String: Bool] {
        if let failure { throw failure }
        return prefs
    }

    func setPreference(type: String, enabled: Bool) async throws(NotificationFailure) {
        if let failure { throw failure }
        written.append((type, enabled))
        prefs = NotificationPrefs.setting(prefs, type: type, enabled: enabled)
    }

    private func read(_ row: AppNotification) -> AppNotification {
        AppNotification(
            id: row.id, type: row.type, title: row.title, body: row.body, link: row.link,
            readAt: "2026-09-11T12:00:00Z", createdAt: row.createdAt, expiresAt: row.expiresAt
        )
    }
}

private func notification(
    _ id: String,
    type: NotificationType = .memberJoined,
    unread: Bool = true
) -> AppNotification {
    AppNotification(
        id: id,
        type: type.rawValue,
        title: "Title \(id)",
        body: "Body \(id)",
        link: nil,
        readAt: unread ? nil : "2026-09-10T12:00:00Z",
        createdAt: "2026-09-11T12:00:00Z",
        expiresAt: nil
    )
}

@Suite("Notification feed")
@MainActor
struct NotificationsPresenterTests {

    @Test("An empty feed says so rather than showing a blank list")
    func emptyFeed() async {
        let presenter = NotificationsPresenter(notifications: StubNotifications())
        await presenter.appeared()
        #expect(presenter.viewState.content == .empty(message: NotificationCopy.empty))
        #expect(presenter.viewState.badgeText == nil)
    }

    @Test("Unread rows are marked, and counted into a badge")
    func badge() async {
        let stub = StubNotifications()
        stub.rows = [notification("a"), notification("b"), notification("c", unread: false)]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        #expect(presenter.viewState.badgeText == "2")
        #expect(presenter.viewState.isMarkAllEnabled)

        guard case .rows(let rows) = presenter.viewState.content else {
            Issue.record("Expected rows")
            return
        }
        #expect(rows.map(\.isUnread) == [true, true, false])
    }

    @Test("Tapping an unread row marks it; tapping a read one writes nothing")
    func tapping() async {
        let stub = StubNotifications()
        stub.rows = [notification("a"), notification("b", unread: false)]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        await presenter.rowTapped("a")
        #expect(stub.markedRead == ["a"])

        await presenter.rowTapped("b")
        #expect(stub.markedRead == ["a"])
    }

    @Test("Mark-all is offered only when something is unread")
    func markAllGating() async {
        let stub = StubNotifications()
        stub.rows = [notification("a", unread: false)]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        #expect(!presenter.viewState.isMarkAllEnabled)
        await presenter.markAllReadTapped()
        #expect(stub.markAllCount == 0)
    }

    @Test("Marking all read clears the badge")
    func markAll() async {
        let stub = StubNotifications()
        stub.rows = [notification("a"), notification("b")]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        await presenter.markAllReadTapped()

        #expect(stub.markAllCount == 1)
        #expect(presenter.viewState.badgeText == nil)
    }

    @Test("Deleting removes the row")
    func deleting() async {
        let stub = StubNotifications()
        stub.rows = [notification("a"), notification("b")]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        await presenter.deleteTapped("a")

        #expect(stub.deleted == ["a"])
        guard case .rows(let rows) = presenter.viewState.content else {
            Issue.record("Expected rows")
            return
        }
        #expect(rows.map(\.id) == ["b"])
    }

    @Test("A failed read says so rather than looking empty")
    func failure() async {
        let stub = StubNotifications()
        stub.failure = .network
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        #expect(presenter.viewState.content
            == .failed(message: NotificationCopy.message(for: .network)))
    }

    @Test("A type this client has never heard of still draws something")
    func unknownTypeStillRenders() async {
        let stub = StubNotifications()
        stub.rows = [
            AppNotification(
                id: "x", type: "invented_next_year", title: "Something new", body: nil,
                link: nil, readAt: nil, createdAt: "2026-09-11T12:00:00Z", expiresAt: nil
            ),
        ]
        let presenter = NotificationsPresenter(notifications: stub)
        await presenter.appeared()

        guard case .rows(let rows) = presenter.viewState.content else {
            Issue.record("Expected rows")
            return
        }
        #expect(!rows[0].symbol.isEmpty)
    }
}

@Suite("Notification settings")
@MainActor
struct NotificationSettingsPresenterTests {

    @Test("Every type is listed, and on by default")
    func defaultsAreOn() async {
        let presenter = NotificationSettingsPresenter(notifications: StubNotifications())
        await presenter.appeared()

        let toggles = presenter.viewState.toggles
        let ids = toggles.map(\.id)
        let everyOneOn = toggles.allSatisfy(\.isOn)
        #expect(ids == NotificationType.allCases.map(\.rawValue))
        #expect(everyOneOn)
    }

    @Test("A type turned off elsewhere shows as off here")
    func storedPreferenceIsRead() async {
        let stub = StubNotifications()
        stub.prefs = ["nudge_request": false]
        let presenter = NotificationSettingsPresenter(notifications: stub)
        await presenter.appeared()

        let nudgeToggle = presenter.viewState.toggles.first { $0.id == "nudge_request" }
        #expect(nudgeToggle?.isOn == false)
    }

    @Test("Toggling writes that one type and leaves the rest alone")
    func toggling() async {
        let stub = StubNotifications()
        stub.prefs = ["member_joined": false]
        let presenter = NotificationSettingsPresenter(notifications: stub)
        await presenter.appeared()

        await presenter.toggled("nudge_request", to: false)

        #expect(stub.written.count == 1)
        #expect(stub.written[0].type == "nudge_request")
        #expect(stub.prefs["member_joined"] == false)
        #expect(stub.prefs["nudge_request"] == false)
    }

    /// The switch moves first so it does not spring back mid-write; a failure
    /// has to put it back where it belongs rather than leaving a lie on screen.
    @Test("A failed write puts the switch back and says what happened")
    func failedToggleReverts() async {
        let stub = StubNotifications()
        let presenter = NotificationSettingsPresenter(notifications: stub)
        await presenter.appeared()

        stub.failure = .network
        await presenter.toggled("nudge_request", to: false)

        #expect(presenter.viewState.notice == NotificationCopy.message(for: .network))
    }
}
