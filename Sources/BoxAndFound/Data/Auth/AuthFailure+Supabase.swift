import Foundation
import Supabase

/// The one place that knows supabase-swift's error shape.
///
/// Deliberately separate from the pure mapper: when the SDK changes its error
/// taxonomy this file breaks and the tested logic next door does not.
extension AuthFailure {
    static func from(_ error: Error) -> AuthFailure {
        if let authError = error as? AuthError {
            // `AuthError` exposes `message` and `errorCode` as computed
            // properties across all of its cases, so no per-case switch is
            // needed and new cases cannot silently fall through.
            return authFailure(errorCode: authError.errorCode.rawValue, message: authError.message)
        }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            default: return .network
            }
        }
        return authFailure(errorCode: nil, message: error.localizedDescription)
    }
}
