import Foundation

/// Client-side validation, kept out of the view model so it can be tested
/// directly and reused by both the sign-in and sign-up forms.
///
/// A courtesy check only — it catches obvious typos before a round trip.
/// GoTrue remains the authority on what it will accept.
enum Credentials {

    /// Supabase's default minimum. Raising it here would only lock people out.
    static let minPasswordLength = 6

    /// Excludes spaces, requires a dot-separated host. Kept character-for-
    /// character equivalent to the Android client's regex.
    ///
    /// Computed rather than stored: `Regex` is not `Sendable`, so a `static
    /// let` is a hard error in Swift 6 language mode. Rebuilding a literal
    /// costs almost nothing, and the two alternatives — `nonisolated(unsafe)`
    /// or pinning it to `@MainActor` — would each trade a real guarantee for a
    /// saved allocation.
    private static var email: Regex<(Substring, Substring)> {
        #/^[^@ ]+@[^@ .]+([.][^@ .]+)+$/#
    }

    static func isEmailShaped(_ candidate: String) -> Bool {
        normaliseEmail(candidate).wholeMatch(of: email) != nil
    }

    static func isPasswordLongEnough(_ password: String) -> Bool {
        password.count >= minPasswordLength
    }

    /// Trim only. Case is preserved: GoTrue lowercases addresses itself.
    static func normaliseEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
