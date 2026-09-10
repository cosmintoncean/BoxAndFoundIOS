import Foundation

/// The only place an `AuthFailure` becomes words, and the only place that
/// decides a failure is not worth any.
///
/// It sits in the presentation layer because copy is presentation: the
/// repository never carries a sentence, and the view never sees a GoTrue
/// string. The wording is taken from the Android client's `strings.xml`
/// verbatim, so the same failure reads the same on both phones.
enum AuthCopy {

    /// Nil when the failure should leave no trace on screen. Dismissing a
    /// sign-in sheet is not an error and gets no red box.
    static func notice(for failure: AuthFailure) -> AuthViewState.Notice? {
        guard let text = message(for: failure) else { return nil }
        return AuthViewState.Notice(kind: .error, text: text)
    }

    static let confirmationSent = AuthViewState.Notice(
        kind: .success,
        text: "Account created. Check your email to confirm your address, then sign in."
    )

    /// Deliberately non-committal: GoTrue answers a request for an
    /// unregistered address exactly as it answers a real one, so claiming the
    /// mail was sent would be a guess — and a screen that could tell the two
    /// apart would be a way to find out who has an account.
    static let resetLinkRequested = AuthViewState.Notice(
        kind: .success,
        text: "If that email has an account, a reset link is on its way. It is good for one hour."
    )

    private static func message(for failure: AuthFailure) -> String? {
        switch failure {
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
        case .cancelled:
            nil
        }
    }
}
