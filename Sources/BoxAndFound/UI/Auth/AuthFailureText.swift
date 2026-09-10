import Foundation

/// The only place an `AuthFailure` becomes words. Keeping the mapping here
/// means the repository never carries copy and the screen never sees a GoTrue
/// string.
///
/// The wording is copied from the Android client's `strings.xml` verbatim, so
/// the same failure reads the same on both phones.
extension AuthFailure {
    var message: String {
        switch self {
        case .invalidCredentials:
            "That email and password do not match an account."
        case .emailNotConfirmed:
            "Confirm your email address first — check your inbox for the link."
        case .emailAlreadyRegistered:
            "That email already has an account. Sign in instead."
        case .weakPassword:
            "Pick a longer password — at least \(Credentials.minPasswordLength) characters."
        case .invalidEmail:
            "That does not look like an email address."
        case .rateLimited:
            "Too many attempts. Wait a minute, then try again."
        case .network:
            "No connection. Check your network and try again."
        case .unknown:
            "Something went wrong. Try again."
        // Dismissing a sheet is not an error, so it gets no words. The screen
        // checks `isSilent` rather than rendering an empty string.
        case .cancelled:
            ""
        }
    }

    /// True when the failure should leave no trace on screen.
    var isSilent: Bool { self == .cancelled }
}
