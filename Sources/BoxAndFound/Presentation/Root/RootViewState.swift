import Foundation

/// What `RootView` draws. `SignedInUser` stops here — the screen is handed
/// what the next one needs, not the domain record.
struct RootViewState: Equatable {
    enum Content: Equatable {
        case loading
        case signedOut
        /// The id is the inventory's starting point: every read is scoped to
        /// the households this person belongs to.
        /// An invite code rides along when the app was opened by a link, so
        /// the first screen can carry the person to it rather than dropping
        /// them on the box list.
        case signedIn(userID: String, pendingInviteCode: String?)
        /// A password-reset link was opened. Beats `signedIn` deliberately:
        /// the link signs the person in, so the session cannot say that they
        /// came to set a password rather than to use the app.
        case passwordReset
    }

    var content: Content
}
