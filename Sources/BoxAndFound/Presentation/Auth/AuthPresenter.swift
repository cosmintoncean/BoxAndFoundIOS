import AuthenticationServices
import Foundation
import Observation

/// Drives the sign-in screen. See `Presenter` for what that means here.
@MainActor
@Observable
final class AuthPresenter: Presenter {

    // MARK: - The only state there is

    private var stage: AuthViewState.Stage = .credentials
    private var mode: AuthViewState.Mode = .signIn
    private var name = ""
    private var email = ""
    private var password = ""
    private var isPasswordVisible = false
    private var isSubmitting = false
    private var notice: AuthViewState.Notice?

    /// The raw nonce of an in-flight Sign in with Apple request, held between
    /// the request and its completion — see `AppleNonce`.
    private var pendingAppleNonce: String?

    private let repository: AuthRepository

    init(repository: AuthRepository = AuthRepository()) {
        self.repository = repository
    }

    // MARK: - What the view draws

    /// Derived on every read from the private state above, so there is no
    /// second copy to keep in step. `@Observable` tracks the properties this
    /// touches, so the view redraws when any of them moves.
    var viewState: AuthViewState {
        AuthViewState(
            stage: stage,
            mode: mode,
            modes: [
                .init(mode: .signIn, title: "Sign in"),
                .init(mode: .signUp, title: "Sign up"),
            ],
            heading: heading,
            name: name,
            isNameFieldVisible: mode == .signUp,
            email: email,
            password: password,
            isPasswordVisible: isPasswordVisible,
            passwordHint: mode == .signUp
                ? "At least \(Credentials.minPasswordLength) characters"
                : nil,
            submitTitle: submitTitle,
            isSubmitEnabled: canSubmit,
            isSubmitting: isSubmitting,
            isForgotPasswordOffered: stage == .credentials && mode == .signIn,
            notice: notice,
            providers: [
                .init(kind: .apple, title: "Continue with Apple"),
                .init(kind: .google, title: "Continue with Google"),
                .init(kind: .facebook, title: "Continue with Facebook"),
            ]
        )
    }

    private var heading: String {
        switch stage {
        case .forgotPassword: "Reset your password"
        case .credentials: mode == .signIn ? "Welcome back" : "Create your account"
        }
    }

    private var submitTitle: String {
        switch stage {
        case .forgotPassword: "Send reset link"
        case .credentials: mode == .signIn ? "Sign in" : "Create account"
        }
    }

    /// Only gates the button. GoTrue is still the authority on what it
    /// accepts — this just avoids a round trip for an obvious typo.
    ///
    /// The reset request needs an address and nothing else: the password
    /// field is not on that pane, and gating on it would leave the button
    /// dead for exactly the person who has forgotten the password.
    private var canSubmit: Bool {
        guard !isSubmitting, Credentials.isEmailShaped(email) else { return false }
        return stage == .forgotPassword || Credentials.isPasswordLongEnough(password)
    }

    // MARK: - Intents

    func modeSelected(_ mode: AuthViewState.Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        // Reaching the tabs at all means leaving the reset pane behind.
        stage = .credentials
        // Switching tabs clears the last outcome. A "check your email" notice
        // left hanging over the sign-in form reads as an error.
        notice = nil
    }

    func nameChanged(_ value: String) { name = value }
    func emailChanged(_ value: String) { email = value }
    func passwordChanged(_ value: String) { password = value }
    func passwordVisibilityToggled() { isPasswordVisible.toggle() }

    /// Opens the "email me a link" pane, keeping whatever address was typed.
    func forgotPasswordTapped() {
        stage = .forgotPassword
        notice = nil
    }

    func backToSignInTapped() {
        stage = .credentials
        notice = nil
    }

    func submitTapped() async {
        guard canSubmit else { return }
        if stage == .forgotPassword {
            await perform {
                try await self.repository.sendPasswordReset(email: self.email)
                // Success here only means GoTrue accepted the request: it
                // answers the same way for an address with no account, so
                // saying "sent" would be a guess.
                self.notice = AuthCopy.resetLinkRequested
            }
            return
        }
        await perform {
            switch self.mode {
            case .signIn:
                try await self.repository.signIn(email: self.email, password: self.password)
            case .signUp:
                try await self.repository.signUp(
                    email: self.email,
                    password: self.password,
                    displayName: self.name
                )
                // Sign-up does not sign anyone in: Supabase sends a
                // confirmation mail and the session arrives afterwards.
                self.notice = AuthCopy.confirmationSent
            }
        }
    }

    func providerTapped(_ kind: AuthViewState.ProviderButton.Kind) async {
        // Apple is handled by its own button, which needs the request and
        // completion callbacks rather than a plain tap.
        guard kind != .apple else { return }
        let provider = Self.domainProvider(for: kind)
        await perform { try await self.repository.startOAuth(provider) }
    }

    // MARK: - Sign in with Apple

    func appleRequestPrepared(_ request: ASAuthorizationAppleIDRequest) {
        let raw = AppleNonce.random()
        pendingAppleNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(raw)
    }

    func appleSignInCompleted(_ result: Result<ASAuthorization, Error>) async {
        // Whatever happens, the nonce is spent.
        let raw = pendingAppleNonce
        pendingAppleNonce = nil

        switch result {
        case .failure(let error):
            show(AuthFailure.from(error))
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let raw
            else {
                // Apple returned something this app cannot use. Rare enough
                // that it does not deserve its own copy, but it must not look
                // like success.
                show(.unknown(detail: "Apple returned no usable identity token"))
                return
            }
            await perform {
                try await self.repository.signInWithApple(idToken: idToken, nonce: raw)
            }
        }
    }

    // MARK: -

    private static func domainProvider(
        for kind: AuthViewState.ProviderButton.Kind
    ) -> OAuthProvider {
        switch kind {
        case .apple: .apple
        case .google: .google
        case .facebook: .facebook
        }
    }

    private func perform(_ block: @MainActor () async throws -> Void) async {
        isSubmitting = true
        notice = nil
        defer { isSubmitting = false }
        do {
            try await block()
        } catch let failure as AuthFailure {
            show(failure)
        } catch {
            show(AuthFailure.from(error))
        }
    }

    private func show(_ failure: AuthFailure) {
        notice = AuthCopy.notice(for: failure)
    }
}
