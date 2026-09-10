import Foundation

/// Tells a password-recovery callback apart from any other link the app is
/// opened with.
///
/// A recovery link arrives on the same custom scheme as the OAuth callback and
/// establishes a session exactly as one does, so the session alone cannot say
/// which happened. GoTrue's `type=recovery` marker — in the fragment for the
/// implicit flow, in the query for PKCE — is the only thing that does, and
/// getting it wrong either strands people in the app with the password they
/// forgot or interrupts an ordinary sign-in with a reset form.
enum RecoveryLink {

    static func isRecovery(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return isRecovery(parameters: components.fragment)
            || isRecovery(parameters: components.query)
    }

    /// `type=recovery` as a whole parameter, never as the tail of a longer name
    /// like `token_type=recovery`.
    private static func isRecovery(parameters: String?) -> Bool {
        guard let parameters, !parameters.isEmpty else { return false }
        return parameters
            .split(separator: "&")
            .contains { $0 == "type=recovery" }
    }
}
