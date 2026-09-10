import Foundation
import Observation
import Supabase

/// The single reader of Supabase session state.
///
/// supabase-swift persists and refreshes the session itself, so this owns no
/// session storage of its own — it only narrows the auth state stream to the
/// three cases the UI actually branches on.
///
/// The narrowing is on `session != nil` rather than on `AuthChangeEvent`:
/// the event list grows between SDK releases, and every case that matters here
/// is already answered by whether a session came with it.
@MainActor
@Observable
final class SessionStore {
    private(set) var state: AuthState = .restoring

    private let client: SupabaseClient
    private let allowlist: [String]
    private var watcher: Task<Void, Never>?

    init(client: SupabaseClient = SupabaseProvider.shared,
         allowlist: [String] = Premium.parseEmailList(AppConfig.premiumEmails)) {
        self.client = client
        self.allowlist = allowlist
    }

    /// Starts watching. Idempotent: calling it twice does not open a second
    /// stream, because SwiftUI may run `task` again after a scene change.
    func start() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            guard let self else { return }
            for await (_, session) in self.client.auth.authStateChanges {
                self.state = Self.narrow(session, allowlist: self.allowlist)
            }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
    }

    func signOut() async {
        // A failed sign-out still means the person wants out; the stream will
        // report what actually happened either way.
        try? await client.auth.signOut()
    }

    private static func narrow(_ session: Session?, allowlist: [String]) -> AuthState {
        guard let session else { return .signedOut }
        let user = session.user
        let meta = user.userMetadata
        return .signedIn(
            SignedInUser(
                id: user.id.uuidString,
                email: user.email,
                isPremium: Premium.isPremium(
                    email: user.email,
                    isPremiumFlag: meta["is_premium"]?.boolValue,
                    plan: meta["premium_plan"]?.stringValue,
                    until: meta["premium_until"]?.stringValue,
                    allowlist: allowlist,
                    now: Date()
                )
            )
        )
    }
}
