import Foundation
import Supabase

/// How the domain names a provider, in the SDK's own terms. The only place
/// the two vocabularies meet.
extension OAuthProvider {
    var supabase: Provider {
        switch self {
        case .google: .google
        case .facebook: .facebook
        case .apple: .apple
        }
    }
}

/// Every way into an account.
///
/// Ported from the Android `AuthRepository`. The one shape change is the error
/// channel: Kotlin returns `Result<Unit>` wrapping an `AuthException`, where
/// Swift throws the `AuthFailure` itself. Wrapping it in a second type would
/// buy nothing here — `.unknown` already carries the original text for logs.
struct AuthRepository: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    /// supabase-swift updates its own session state on success and
    /// `SessionStore` observes that, so nothing here hands a session back.
    func signIn(email: String, password: String) async throws(AuthFailure) {
        try await run {
            try await client.auth.signIn(
                email: Credentials.normaliseEmail(email),
                password: password
            )
        }
    }

    /// Matches the web client: the display name goes into `user_metadata` as
    /// `display_name`, and Supabase is left to send its own confirmation email.
    func signUp(email: String, password: String, displayName: String?) async throws(AuthFailure) {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata: [String: AnyJSON]? = trimmedName.flatMap {
            $0.isEmpty ? nil : ["display_name": .string($0)]
        }
        try await run {
            try await client.auth.signUp(
                email: Credentials.normaliseEmail(email),
                password: password,
                data: metadata
            )
        }
    }

    /// Sign in with Apple, native. The ID token comes from the system sheet
    /// rather than a browser round trip, and `nonce` is the *raw* nonce whose
    /// SHA-256 was put on the original request — GoTrue rehashes it to check.
    func signInWithApple(idToken: String, nonce: String) async throws(AuthFailure) {
        try await run {
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
        }
    }

    /// Browser-based OAuth for the providers with no native sheet. Unlike the
    /// Android version this does not return when the browser opens: on iOS
    /// `ASWebAuthenticationSession` hands the callback straight back to the
    /// SDK, so the call completes with a session and no deep link is involved.
    func startOAuth(_ provider: OAuthProvider) async throws(AuthFailure) {
        try await run {
            try await client.auth.signInWithOAuth(
                provider: provider.supabase,
                redirectTo: AppConfig.oauthCallback
            )
        }
    }

    /// Email a password-reset link.
    ///
    /// GoTrue answers the same way whether or not the address has an account,
    /// so this cannot be used to find out who is registered — the screen says
    /// as much rather than claiming the mail was sent.
    ///
    /// The link comes back through the same custom scheme the OAuth callback
    /// uses, so tapping it in Mail opens this app rather than the website.
    func sendPasswordReset(email: String) async throws(AuthFailure) {
        try await run {
            try await client.auth.resetPasswordForEmail(
                Credentials.normaliseEmail(email),
                redirectTo: AppConfig.oauthCallback
            )
        }
    }

    /// Complete a recovery link: turn the token it carries into a session.
    ///
    /// Unlike the OAuth flow, nothing hands this back to the SDK on its own —
    /// the link is opened by Mail, not by an `ASWebAuthenticationSession` this
    /// app started, so the URL arrives through `onOpenURL` and has to be
    /// redeemed here.
    func completeRecovery(from url: URL) async throws(AuthFailure) {
        try await run { _ = try await client.auth.session(from: url) }
    }

    /// Set a new password for the session a recovery link established.
    ///
    /// Only meaningful straight after that link is opened: the token it
    /// carries is what authorises the change. An expired or already-spent link
    /// leaves no session, and GoTrue rejects the update rather than changing
    /// anything.
    func updatePassword(_ newPassword: String) async throws(AuthFailure) {
        try await run {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        }
    }
    /// Signs out on every device, as the web client does.
    func signOut() async throws(AuthFailure) {
        try await run { try await client.auth.signOut() }
    }

    private func run(_ block: () async throws -> Void) async throws(AuthFailure) {
        do {
            try await block()
        } catch {
            throw AuthFailure.from(error)
        }
    }
}
