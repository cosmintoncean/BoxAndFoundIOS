import AuthenticationServices
import Foundation
import Supabase

/// The one place that knows supabase-swift's error shape, and the system
/// frameworks' shapes for a person changing their mind.
///
/// Deliberately separate from the pure mapper: when an SDK changes its error
/// taxonomy this file breaks and the tested logic next door does not.
extension AuthFailure {
    static func from(_ error: Error) -> AuthFailure {
        if let authError = error as? AuthError {
            // `AuthError` exposes `message` and `errorCode` as computed
            // properties across all of its cases, so no per-case switch is
            // needed and new cases cannot silently fall through.
            return authFailure(errorCode: authError.errorCode.rawValue, message: authError.message)
        }

        // Dismissing a sheet is not a failure worth words. Each framework
        // spells it differently, and none of them is a GoTrue error.
        if error is CancellationError { return .cancelled }
        if let webAuth = error as? ASWebAuthenticationSessionError,
           webAuth.code == .canceledLogin { return .cancelled }
        if let appleAuth = error as? ASAuthorizationError,
           appleAuth.code == .canceled { return .cancelled }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network
        }

        return authFailure(errorCode: nil, message: error.localizedDescription)
    }
}
