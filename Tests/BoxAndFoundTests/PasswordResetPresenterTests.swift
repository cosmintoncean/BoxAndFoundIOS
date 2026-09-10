import Testing
@testable import BoxAndFound

/// The whole screen without a screen: call intents, read the view state.
@Suite("Password reset presenter")
@MainActor
struct PasswordResetPresenterTests {

    private func presenter() -> PasswordResetPresenter {
        PasswordResetPresenter(onFinished: {})
    }

    @Test("Opens empty, with nothing to save and nothing to complain about")
    func initialState() {
        let state = presenter().viewState
        #expect(state.password.isEmpty)
        #expect(state.confirmation.isEmpty)
        #expect(!state.isSubmitEnabled)
        #expect(!state.isSubmitting)
        #expect(state.mismatchWarning == nil)
        #expect(state.notice == nil)
    }

    @Test("Saving needs two matching passwords GoTrue would accept")
    func gating() {
        let presenter = presenter()

        presenter.passwordChanged("hunter22")
        #expect(!presenter.viewState.isSubmitEnabled)

        presenter.confirmationChanged("hunter23")
        #expect(!presenter.viewState.isSubmitEnabled)

        presenter.confirmationChanged("hunter22")
        #expect(presenter.viewState.isSubmitEnabled)
    }

    @Test("A password GoTrue would reject is stopped here first")
    func tooShort() {
        let presenter = presenter()
        presenter.passwordChanged("12345")
        presenter.confirmationChanged("12345")
        #expect(!presenter.viewState.isSubmitEnabled)
    }

    @Test("The mismatch warning waits for something to compare")
    func mismatchWarning() {
        let presenter = presenter()
        presenter.passwordChanged("hunter22")
        // An untouched confirmation field is not a mistake.
        #expect(presenter.viewState.mismatchWarning == nil)

        presenter.confirmationChanged("hunt")
        #expect(presenter.viewState.mismatchWarning != nil)

        presenter.confirmationChanged("hunter22")
        #expect(presenter.viewState.mismatchWarning == nil)
    }

    @Test("Showing the password reveals both fields at once")
    func visibilityIsShared() {
        let presenter = presenter()
        #expect(!presenter.viewState.isPasswordVisible)
        presenter.passwordVisibilityToggled()
        #expect(presenter.viewState.isPasswordVisible)
    }
}
