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
        #expect(!failure.message.isEmpty)
        #expect(!failure.isSilent)
    }

    @Test("Cancelling is silent, not an error")
    func cancelledIsSilent() {
        #expect(AuthFailure.cancelled.isSilent)
        #expect(AuthFailure.cancelled.message.isEmpty)
    }

    @Test("No GoTrue wording ever reaches the screen")
    func neverLeaksServerText() {
        let leak = AuthFailure.unknown(detail: "AuthApiError: Invalid login credentials")
        #expect(!leak.message.contains("AuthApiError"))
        #expect(leak.message == "Something went wrong. Try again.")
    }

    @Test("The weak-password copy quotes the same minimum the check uses")
    func weakPasswordQuotesTheRule() {
        #expect(AuthFailure.weakPassword.message.contains("\(Credentials.minPasswordLength)"))
    }
}
