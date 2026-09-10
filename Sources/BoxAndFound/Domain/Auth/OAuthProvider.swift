import Foundation

/// Which third-party button was pressed.
///
/// The mapping onto a Supabase `Provider` lives in the data layer, so nothing
/// here depends on the SDK; the presentation layer has its own button kind, so
/// nothing on screen depends on this.
enum OAuthProvider: String, CaseIterable, Sendable {
    case google, facebook, apple
}
