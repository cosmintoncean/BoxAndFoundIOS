import Foundation

/// What `RootView` draws. `SignedInUser` stops here — the screen is handed
/// words, not a domain record.
struct RootViewState: Equatable {
    enum Content: Equatable {
        case loading
        case signedOut
        case signedIn(title: String, subtitle: String)
    }

    var content: Content
}
