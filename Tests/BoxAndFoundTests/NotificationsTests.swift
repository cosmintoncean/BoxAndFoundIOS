import Foundation
import Testing
@testable import BoxAndFound

/// The convention is the server's, and getting it backwards would silently
/// mute every existing user the moment a new type shipped. That is why it is
/// tested rather than trusted.
@Suite("Notification preferences")
struct NotificationPrefsTests {

    @Test("Only an explicit false disables a type")
    func onlyFalseDisables() {
        #expect(!NotificationPrefs.isEnabled(["nudge_request": false], type: "nudge_request"))
        #expect(NotificationPrefs.isEnabled(["nudge_request": true], type: "nudge_request"))
    }

    /// A type the server adds tomorrow is on for everyone until they opt out.
    /// Modelling absence as "off" would mute it for every existing user.
    @Test("A type nobody has an opinion about is enabled")
    func absentMeansEnabled() {
        #expect(NotificationPrefs.isEnabled([:], type: "member_joined"))
        #expect(NotificationPrefs.isEnabled(["nudge_request": false], type: "something_new"))
    }

    @Test("Toggling one type leaves every other alone")
    func togglingPreservesTheRest() {
        let before = ["nudge_request": false, "member_joined": true]
        let after = NotificationPrefs.setting(before, type: "premium_expiring", enabled: false)

        #expect(after["premium_expiring"] == false)
        #expect(after["nudge_request"] == false)
        #expect(after["member_joined"] == true)
    }

    /// The other clients write the whole object, so dropping a key here would
    /// re-enable a type someone had turned off on another device.
    @Test("Turning one back on does not resurrect the others")
    func reenablingIsNarrow() {
        let before = ["nudge_request": false, "member_joined": false]
        let after = NotificationPrefs.setting(before, type: "nudge_request", enabled: true)

        #expect(after["nudge_request"] == true)
        #expect(after["member_joined"] == false)
    }

    @Test("Every type the server produces today has a key this client knows")
    func knownTypes() {
        #expect(NotificationType.allCases.map(\.rawValue).sorted()
            == ["member_joined", "nudge_request", "premium_expiring"])
    }
}

@Suite("Nudge cooldown")
struct NudgeCooldownTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Never nudged means go ahead")
    func neverNudged() {
        #expect(NudgeCooldown.availability(lastSentAt: nil, now: now) == .available)
    }

    @Test("Just nudged means nearly a full day left")
    func justNudged() {
        let availability = NudgeCooldown.availability(lastSentAt: now, now: now)
        #expect(availability == .onCooldown(remaining: NudgeCooldown.duration))
    }

    @Test("An hour in leaves twenty-three")
    func partway() {
        let sent = now.addingTimeInterval(-3600)
        #expect(
            NudgeCooldown.availability(lastSentAt: sent, now: now)
                == .onCooldown(remaining: NudgeCooldown.duration - 3600)
        )
    }

    @Test("A second past the window is available again")
    func justPastTheWindow() {
        let sent = now.addingTimeInterval(-(NudgeCooldown.duration + 1))
        #expect(NudgeCooldown.availability(lastSentAt: sent, now: now) == .available)
    }

    @Test("Exactly on the boundary is available, not blocked")
    func onTheBoundary() {
        let sent = now.addingTimeInterval(-NudgeCooldown.duration)
        #expect(NudgeCooldown.availability(lastSentAt: sent, now: now) == .available)
    }

    /// A row whose timestamp is ahead of this device's clock would otherwise
    /// lock someone out for longer than the rule allows — days, if the skew is
    /// days.
    @Test("A timestamp from the future cannot block for more than the window")
    func futureTimestampIsCapped() {
        let sent = now.addingTimeInterval(7 * 24 * 60 * 60)
        guard case .onCooldown(let remaining) =
            NudgeCooldown.availability(lastSentAt: sent, now: now)
        else {
            Issue.record("Expected a cooldown")
            return
        }
        #expect(remaining == NudgeCooldown.duration)
    }

    @Test("The window matches the interval the server enforces")
    func windowIsTwentyFourHours() {
        #expect(NudgeCooldown.duration == 24 * 60 * 60)
    }
}
