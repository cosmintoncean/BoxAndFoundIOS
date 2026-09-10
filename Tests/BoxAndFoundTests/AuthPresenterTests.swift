import Testing
@testable import BoxAndFound

/// Exercises the whole screen without a screen: call intents, read the view
/// state. That is the point of the presenter owning both.
@Suite("Auth presenter")
@MainActor
struct AuthPresenterTests {

    @Test("Opens on sign-in, with nothing filled in and nothing to say")
    func initialState() {
        let state = AuthPresenter().viewState
        #expect(state.mode == .signIn)
        #expect(state.heading == "Welcome back")
        #expect(state.submitTitle == "Sign in")
        #expect(!state.isSubmitEnabled)
        #expect(!state.isSubmitting)
        #expect(!state.isNameFieldVisible)
        #expect(state.passwordHint == nil)
        #expect(state.notice == nil)
    }

    @Test("Typing goes through the presenter and comes back out in the state")
    func typing() {
        let presenter = AuthPresenter()
        presenter.emailChanged("someone@example.com")
        presenter.passwordChanged("123456")
        presenter.nameChanged("Cosmin")

        let state = presenter.viewState
        #expect(state.email == "someone@example.com")
        #expect(state.password == "123456")
        #expect(state.name == "Cosmin")
    }

    @Test("The button stays shut until both fields could plausibly work")
    func gating() {
        let presenter = AuthPresenter()
        presenter.emailChanged("not-an-email")
        presenter.passwordChanged("longenough")
        #expect(!presenter.viewState.isSubmitEnabled)

        presenter.emailChanged("someone@example.com")
        presenter.passwordChanged("12345")
        #expect(!presenter.viewState.isSubmitEnabled)

        presenter.passwordChanged("123456")
        #expect(presenter.viewState.isSubmitEnabled)
    }

    @Test("Signing up asks for a name but never requires one")
    func signUpShape() {
        let presenter = AuthPresenter()
        presenter.modeSelected(.signUp)
        presenter.emailChanged("someone@example.com")
        presenter.passwordChanged("123456")

        let state = presenter.viewState
        #expect(state.heading == "Create your account")
        #expect(state.submitTitle == "Create account")
        #expect(state.isNameFieldVisible)
        #expect(state.passwordHint == "At least \(Credentials.minPasswordLength) characters")
        #expect(state.name.isEmpty)
        #expect(state.isSubmitEnabled)
    }

    @Test("What was typed survives switching tabs")
    func switchingKeepsInput() {
        let presenter = AuthPresenter()
        presenter.emailChanged("someone@example.com")
        presenter.modeSelected(.signUp)
        #expect(presenter.viewState.email == "someone@example.com")
        #expect(presenter.viewState.notice == nil)
    }

    @Test("The eye toggles, and only the eye")
    func passwordVisibility() {
        let presenter = AuthPresenter()
        presenter.passwordChanged("hunter22")
        #expect(!presenter.viewState.isPasswordVisible)

        presenter.passwordVisibilityToggled()
        #expect(presenter.viewState.isPasswordVisible)
        #expect(presenter.viewState.password == "hunter22")

        presenter.passwordVisibilityToggled()
        #expect(!presenter.viewState.isPasswordVisible)
    }

    @Test("Forgetting the password swaps the pane, keeping the address typed")
    func forgotPane() {
        let presenter = AuthPresenter()
        presenter.emailChanged("someone@example.com")
        #expect(presenter.viewState.isForgotPasswordOffered)

        presenter.forgotPasswordTapped()
        let state = presenter.viewState
        #expect(state.stage == .forgotPassword)
        #expect(state.heading == "Reset your password")
        #expect(state.submitTitle == "Send reset link")
        #expect(state.email == "someone@example.com")
        // Nothing to forget on this pane, so nothing to offer.
        #expect(!state.isForgotPasswordOffered)
    }

    @Test("The reset request needs only an address")
    func forgotGating() {
        let presenter = AuthPresenter()
        presenter.forgotPasswordTapped()
        // The password field is not on that pane, so gating on it would leave
        // the button dead for exactly the person who has forgotten it.
        #expect(!presenter.viewState.isSubmitEnabled)

        presenter.emailChanged("someone@example.com")
        #expect(presenter.viewState.isSubmitEnabled)

        presenter.emailChanged("not-an-email")
        #expect(!presenter.viewState.isSubmitEnabled)
    }

    @Test("Backing out, or reaching for a tab, returns to the form")
    func leavingTheForgotPane() {
        let presenter = AuthPresenter()
        presenter.forgotPasswordTapped()
        presenter.backToSignInTapped()
        #expect(presenter.viewState.stage == .credentials)
        #expect(presenter.viewState.heading == "Welcome back")

        presenter.forgotPasswordTapped()
        presenter.modeSelected(.signUp)
        #expect(presenter.viewState.stage == .credentials)
    }

    /// There is no way to tell an address with an account from one without,
    /// and the copy must not imply otherwise.
    @Test("The reset confirmation does not claim the mail was sent")
    func resetConfirmationHedges() {
        let text = AuthCopy.resetLinkRequested.text
        #expect(AuthCopy.resetLinkRequested.kind == .success)
        #expect(text.contains("If that email has an account"))
    }
    /// Apple's guideline is that Sign in with Apple is at least as prominent
    /// as any other third-party option. Ordering is decided by the presenter,
    /// so it can be checked here rather than by eye.
    @Test("Apple is offered first, above the other providers")
    func appleComesFirst() {
        let providers = AuthPresenter().viewState.providers
        #expect(providers.map(\.kind) == [.apple, .google, .facebook])
        #expect(providers.allSatisfy { !$0.title.isEmpty })
    }
}
