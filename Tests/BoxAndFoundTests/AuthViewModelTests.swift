import Testing
@testable import BoxAndFound

@Suite("Auth form gating")
@MainActor
struct AuthViewModelTests {

    @Test("The button stays shut until both fields could plausibly work")
    func gating() {
        let viewModel = AuthViewModel()
        #expect(!viewModel.canSubmit)

        viewModel.email = "not-an-email"
        viewModel.password = "longenough"
        #expect(!viewModel.canSubmit)

        viewModel.email = "someone@example.com"
        viewModel.password = "12345"
        #expect(!viewModel.canSubmit)

        viewModel.password = "123456"
        #expect(viewModel.canSubmit)
    }

    @Test("A missing name never blocks sign-up — it is optional, as on the web")
    func nameIsOptional() {
        let viewModel = AuthViewModel()
        viewModel.mode = .signUp
        viewModel.email = "someone@example.com"
        viewModel.password = "123456"
        #expect(viewModel.name.isEmpty)
        #expect(viewModel.canSubmit)
    }

    @Test("Switching tabs clears the previous outcome")
    func switchingTabsClearsOutcome() {
        let viewModel = AuthViewModel()
        viewModel.mode = .signUp
        viewModel.mode = .signIn
        #expect(viewModel.visibleFailure == nil)
        #expect(!viewModel.confirmationSent)
    }

    @Test("Each mode names itself the way the Android client does")
    func copy() {
        #expect(AuthViewModel.Mode.signIn.title == "Sign in")
        #expect(AuthViewModel.Mode.signIn.action == "Sign in")
        #expect(AuthViewModel.Mode.signIn.heading == "Welcome back")
        #expect(AuthViewModel.Mode.signUp.title == "Sign up")
        #expect(AuthViewModel.Mode.signUp.action == "Create account")
        #expect(AuthViewModel.Mode.signUp.heading == "Create your account")
    }
}
