import Foundation

/// Build-time configuration, read back out of the Info.plist that
/// `Config/Secrets.xcconfig` populates. The iOS counterpart of the Android
/// client's `BuildConfig` fields.
enum AppConfig {

    static var supabaseURL: URL? {
        guard let raw = string("SupabaseURL"), !raw.contains("YOUR-PROJECT") else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String? {
        guard let key = string("SupabaseAnonKey"), key != "your-anon-key" else { return nil }
        return key
    }

    static var premiumEmails: String? { string("PremiumEmails") }

    /// The private bucket box photos live in. Not a secret — the same value
    /// the web client and Android both use — so it falls back rather than
    /// failing a build that has not set it.
    static var storageBucket: String { string("StorageBucket") ?? "box-images" }

    /// Where invite and box links point. Not a secret, and identical on every
    /// client — a link built here has to open the same thing the web client
    /// would open.
    static var siteURL: String { string("SiteURL") ?? "https://boxandfound.net" }

    /// True when this build was given real credentials rather than the
    /// stand-ins CI writes for a pull request from a fork. Tests that need a
    /// live backend switch themselves off when it is false, so a fork can
    /// still get a green run without ever seeing a secret.
    static var isLiveBackendConfigured: Bool {
        guard let host = supabaseURL?.host() else { return false }
        return !host.hasPrefix("ci-placeholder")
    }

    /// The redirect OAuth providers hand the session back through. Must be
    /// allowlisted in Supabase -> Authentication -> URL Configuration, next to
    /// the Android client's `net.boxandfound.android://login-callback`.
    static let oauthCallback = URL(string: "net.boxandfound.ios://login-callback")!

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
