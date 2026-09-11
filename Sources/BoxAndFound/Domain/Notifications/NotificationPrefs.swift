import Foundation

/// Per-type notification preferences, stored on `user_metadata.notif_prefs`.
///
/// The convention is the server's, enforced by `notif_type_disabled` in
/// `MIGRATION_notification_prefs.sql`: **only an explicit `false` disables a
/// type.** Missing means enabled, so a type added server-side is on for
/// everyone until they opt out.
///
/// Modelling this as "absent means off" would silently mute every existing
/// user the moment a new type shipped, which is why it is pure and tested
/// rather than inlined into a presenter.
enum NotificationPrefs {

    /// Whether `type` is enabled given the stored map. An unknown type is
    /// enabled, which is the whole point.
    static func isEnabled(_ prefs: [String: Bool], type: String) -> Bool {
        prefs[type] != false
    }

    /// The map to write back after toggling one type.
    ///
    /// Every other entry is preserved: the web and Android clients write the
    /// whole object too, so dropping a key here would re-enable a type someone
    /// had turned off on another device.
    static func setting(_ prefs: [String: Bool], type: String, enabled: Bool) -> [String: Bool] {
        var merged = prefs
        merged[type] = enabled
        return merged
    }
}
