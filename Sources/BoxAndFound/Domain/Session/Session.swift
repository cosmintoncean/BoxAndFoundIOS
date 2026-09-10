import Foundation

/// What the rest of the app is allowed to know about the session.
///
/// Domain, not presentation: no strings a person reads, no formatting. A
/// presenter turns this into something a screen can draw.
enum AuthState: Equatable, Sendable {
    /// Session is being restored from the keychain on cold start.
    case restoring
    case signedOut
    case signedIn(SignedInUser)
}

struct SignedInUser: Equatable, Sendable {
    let id: String
    let email: String?
    /// Derived from `user_metadata` exactly as the web and Android clients
    /// derive it, so one purchase reads the same everywhere. See `Premium`.
    let isPremium: Bool
}
