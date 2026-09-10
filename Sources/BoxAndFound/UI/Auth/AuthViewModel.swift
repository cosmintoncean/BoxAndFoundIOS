import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {

    enum Mode: CaseIterable, Identifiable {
        case signIn, signUp

        var id: Self { self }
        var title: String { self == .signIn ? "Sign in" : "Sign up" }
        var heading: String { self == .signIn ? "Welcome back" : "Create your account" }
        var action: String { self == .signIn ? "Sign in" : "Create account" }
    }

    var mode: Mode = .signIn {
        didSet {
            guard mode != oldValue else { return }
            // Switching tabs clears the last outcome. A "check your email"
            // notice left hanging over the sign-in form reads as an error.
            failure = nil
            confirmationSent = false
        }
    }

    var name = ""
    var email = ""
    var password = ""
    var passwordVisible = false

    private(set) var submitting = false
    private(set) var failure: AuthFailure?
    private(set) var confirmationSent = false

    /// The raw nonce of an in-flight Sign in with Apple request. Held between
    /// the button's request and its completion — see `AppleNonce`.
    private var pendingAppleNonce: String?

    private let repository: AuthRepository

    init(repository: AuthRepository = AuthRepository()) {
        self.repository = repository
    }

    /// Only gates the button. GoTrue is still the authority on what it
    /// accepts — this just avoids a round trip for an obvious typo.
    var canSubmit: Bool {
        !submitting
            && Credentials.isEmailShaped(email)
            && Credentials.isPasswordLongEnough(password)
    }

    /// Non-nil only when there is something worth showing a person.
    var visibleFailure: AuthFailure? {
        guard let failure, !failure.isSilent else { return nil }
        return failure
    }

    func submit() async {
        guard canSubmit else { return }
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
                // confirmation mail and the session only arrives afterwards.
                self.confirmationSent = true
            }
        }
    }

    func startOAuth(_ provider: OAuthProvider) async {
        await perform { try await self.repository.startOAuth(provider) }
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let raw = AppleNonce.random()
        pendingAppleNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(raw)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        // Whatever happens, the nonce is spent.
        let raw = pendingAppleNonce
        pendingAppleNonce = nil

        switch result {
        case .failure(let error):
            failure = AuthFailure.from(error)
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
                failure = .unknown(detail: "Apple returned no usable identity token")
                return
            }
            await perform { try await self.repository.signInWithApple(idToken: idToken, nonce: raw) }
        }
    }

    // MARK: -

    private func perform(_ block: @MainActor () async throws -> Void) async {
        submitting = true
        failure = nil
        confirmationSent = false
        defer { submitting = false }
        do {
            try await block()
        } catch let authFailure as AuthFailure {
            failure = authFailure
        } catch {
            failure = AuthFailure.from(error)
        }
    }
}
