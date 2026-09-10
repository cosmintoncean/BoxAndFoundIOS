import Foundation

/// Everything `PasswordResetView` draws, and nothing it does not.
///
/// The same contract as `AuthViewState`: varying content only — values,
/// enablement, notices — with fixed field labels left in the view.
struct PasswordResetViewState: Equatable {
    var password: String
    var confirmation: String
    var isPasswordVisible: Bool

    /// Shown under the confirmation field, nil while there is nothing to
    /// disagree about. Someone half-way through retyping has not made a
    /// mistake yet.
    var mismatchWarning: String?
    var passwordHint: String

    var isSubmitEnabled: Bool
    var isSubmitting: Bool
    var notice: AuthViewState.Notice?
}
