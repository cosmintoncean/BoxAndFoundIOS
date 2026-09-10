import Testing
@testable import BoxAndFound

@Suite("Auth copy")
struct AuthCopyTests {

    /// Every case listed by hand: associated values mean the compiler cannot
    /// hand us an `allCases`, and a case added without copy should be noticed
    /// here rather than shipped as an empty red box.
    @Test("Every failure a person can see has words", arguments: [
        AuthFailure.invalidCredentials, .emailNotConfirmed, .emailAlreadyRegistered,
        .weakPassword, .invalidEmail, .rateLimited, .network,
        .unknown(detail: nil), .unknown(detail: "some server text"),
    ])
    func hasCopy(_ failure: AuthFailure) {
        let notice = AuthCopy.notice(for: failure)
        #expect(notice != nil)
        #expect(notice?.text.isEmpty == false)
        #expect(notice?.kind == .error)
    }

    @Test("Cancelling produces no notice at all, rather than an empty one")
    func cancellingIsSilent() {
        #expect(AuthCopy.notice(for: .cancelled) == nil)
    }

    @Test("No GoTrue wording ever reaches the screen")
    func neverLeaksServerText() {
        let leak = AuthFailure.unknown(detail: "AuthApiError: Invalid login credentials")
        let notice = AuthCopy.notice(for: leak)
        #expect(notice?.text.contains("AuthApiError") == false)
        #expect(notice?.text == "Something went wrong. Try again.")
    }

    @Test("The weak-password copy quotes the same minimum the check uses")
    func weakPasswordQuotesTheRule() {
        #expect(
            AuthCopy.notice(for: .weakPassword)?.text
                .contains("\(Credentials.minPasswordLength)") == true
        )
    }

    @Test("A confirmation is good news, and coloured like it")
    func confirmationIsSuccess() {
        #expect(AuthCopy.confirmationSent.kind == .success)
        #expect(AuthCopy.confirmationSent.text.contains("Check your email"))
    }
}
