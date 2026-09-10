import Foundation
import Observation

/// Drives the "choose a new password" screen — step two of a reset, on the
/// other side of the emailed link.
///
/// Separate from `AuthPresenter` because it runs in a different situation: by
/// the time this is on screen the recovery link has already signed the person
/// in, and the only thing left is the password change that sign-in was for.
@MainActor
@Observable
final class PasswordResetPresenter: Presenter {

    private var password = ""
    private var confirmation = ""
    private var isPasswordVisible = false
    private var isSubmitting = false
    private var notice: AuthViewState.Notice?

    private let repository: AuthRepository
    /// Called once the password is set, or the person backs out — whichever
    /// happens, this screen is done and the root goes back to deciding for
    /// itself.
    private let onFinished: () -> Void

    init(repository: AuthRepository = AuthRepository(), onFinished: @escaping () -> Void) {
        self.repository = repository
        self.onFinished = onFinished
    }

    var viewState: PasswordResetViewState {
        PasswordResetViewState(
            password: password,
            confirmation: confirmation,
            isPasswordVisible: isPasswordVisible,
            mismatchWarning: hasMismatch ? Self.mismatchText : nil,
            passwordHint: "At least \(Credentials.minPasswordLength) characters",
            isSubmitEnabled: canSubmit,
            isSubmitting: isSubmitting,
            notice: notice
        )
    }

    /// Only a mismatch worth complaining about: an empty confirmation is a
    /// field not yet typed in, not a wrong one.
    private var hasMismatch: Bool {
        !confirmation.isEmpty && confirmation != password
    }

    private var canSubmit: Bool {
        !isSubmitting
            && Credentials.isPasswordLongEnough(password)
            && confirmation == password
    }

    // MARK: - Intents

    func passwordChanged(_ value: String) {
        password = value
        notice = nil
    }

    func confirmationChanged(_ value: String) {
        confirmation = value
        notice = nil
    }

    func passwordVisibilityToggled() { isPasswordVisible.toggle() }

    func submitTapped() async {
        guard canSubmit else { return }
        isSubmitting = true
        notice = nil
        defer { isSubmitting = false }

        do {
            try await repository.updatePassword(password)
            // The recovery link already established the session, so there is
            // nothing to sign in to — handing control back is the whole exit.
            onFinished()
        } catch let failure as AuthFailure {
            notice = AuthCopy.notice(for: failure)
        } catch {
            notice = AuthCopy.notice(for: AuthFailure.from(error))
        }
    }

    /// Backing out: sign out rather than leaving someone in the app on a
    /// session that came from a mailed link they decided not to use.
    func cancelTapped() async {
        try? await repository.signOut()
        onFinished()
    }

    private static let mismatchText = "Those two passwords do not match."
}
