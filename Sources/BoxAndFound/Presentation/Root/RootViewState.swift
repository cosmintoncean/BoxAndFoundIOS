import Foundation

/// What `RootView` draws. `SignedInUser` stops here — the screen is handed
/// what the next one needs, not the domain record.
struct RootViewState: Equatable {
    enum Content: Equatable {
        case loading
        case signedOut
        /// The id is the inventory's starting point: every read is scoped to
        /// the households this person belongs to.
        case signedIn(userID: String)
    }

    var content: Content
}
