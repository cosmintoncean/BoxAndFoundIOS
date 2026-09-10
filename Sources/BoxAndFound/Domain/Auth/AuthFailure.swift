import Foundation

/// Sign-in and sign-up failures, narrowed to the cases worth telling a person
/// apart.
///
/// Ported from the Android client's `AuthFailure`. The web client puts
/// Supabase's raw `error.message` straight on screen, which leaks server
/// wording into the product, cannot be translated, and changes whenever GoTrue
/// changes. Mapping to a closed set here means the UI picks its own copy.
enum AuthFailure: Error, Equatable, Sendable {
    case invalidCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case weakPassword
    case invalidEmail
    case rateLimited
    case network
    case cancelled

    /// Anything unrecognised. `detail` is for logs, not for the screen.
    case unknown(detail: String?)
}

/// Maps a GoTrue error code (or, failing that, its message) onto `AuthFailure`.
///
/// Pure, so it is testable without a Supabase client — the error taxonomy is
/// the part most likely to drift when GoTrue is upgraded. The code and message
/// tables mirror the Android client's `authFailureOf`, so a given server error
/// produces the same case on both platforms. The one divergence is the network
/// row: URLSession phrases connectivity failures differently from OkHttp, and
/// `AuthFailure.from` catches `URLError` before the text ever reaches here.
func authFailure(errorCode: String?, message: String?) -> AuthFailure {
    switch errorCode?.lowercased() {
    case "invalid_credentials": return .invalidCredentials
    case "email_not_confirmed": return .emailNotConfirmed
    case "user_already_exists", "email_exists": return .emailAlreadyRegistered
    case "weak_password": return .weakPassword
    case "validation_failed": return .invalidEmail
    case "over_request_rate_limit", "over_email_send_rate_limit": return .rateLimited
    default: break
    }

    let text = message?.lowercased() ?? ""
    if text.isEmpty { return .unknown(detail: message) }

    func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

    if has("invalid login credentials") { return .invalidCredentials }
    if has("email not confirmed") { return .emailNotConfirmed }
    if has("already registered", "already been registered") { return .emailAlreadyRegistered }
    if has("password should be", "weak password") { return .weakPassword }
    if has("unable to validate email", "invalid email") { return .invalidEmail }
    if has("rate limit", "too many requests") { return .rateLimited }
    if has("could not connect", "offline", "timed out", "timeout", "network") { return .network }
    return .unknown(detail: message)
}
