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
