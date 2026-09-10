import Testing
@testable import BoxAndFound

@Suite("Auth failure mapping")
struct AuthFailureTests {

    @Test("GoTrue error codes win over the message")
    func codesTakePrecedence() {
        #expect(authFailure(errorCode: "invalid_credentials", message: "anything") == .invalidCredentials)
        #expect(authFailure(errorCode: "email_not_confirmed", message: nil) == .emailNotConfirmed)
        #expect(authFailure(errorCode: "user_already_exists", message: nil) == .emailAlreadyRegistered)
        #expect(authFailure(errorCode: "email_exists", message: nil) == .emailAlreadyRegistered)
        #expect(authFailure(errorCode: "weak_password", message: nil) == .weakPassword)
        #expect(authFailure(errorCode: "validation_failed", message: nil) == .invalidEmail)
        #expect(authFailure(errorCode: "over_request_rate_limit", message: nil) == .rateLimited)
        #expect(authFailure(errorCode: "over_email_send_rate_limit", message: nil) == .rateLimited)
    }

    @Test("Codes are matched case-insensitively")
    func codeCasing() {
        #expect(authFailure(errorCode: "INVALID_CREDENTIALS", message: nil) == .invalidCredentials)
    }

    @Test("Falls back to the message when the code is unknown")
    func messageFallback() {
        #expect(authFailure(errorCode: nil, message: "Invalid login credentials") == .invalidCredentials)
        #expect(authFailure(errorCode: "some_new_code", message: "Email not confirmed") == .emailNotConfirmed)
        #expect(authFailure(errorCode: nil, message: "User already registered") == .emailAlreadyRegistered)
        #expect(authFailure(errorCode: nil, message: "Password should be at least 6 characters") == .weakPassword)
        #expect(authFailure(errorCode: nil, message: "Unable to validate email address") == .invalidEmail)
        #expect(authFailure(errorCode: nil, message: "Email rate limit exceeded") == .rateLimited)
        #expect(authFailure(errorCode: nil, message: "The request timed out") == .network)
    }

    @Test("An unrecognised failure keeps its detail for the log, not the screen")
    func unknownKeepsDetail() {
        #expect(authFailure(errorCode: nil, message: "kaboom") == .unknown(detail: "kaboom"))
        #expect(authFailure(errorCode: nil, message: nil) == .unknown(detail: nil))
        #expect(authFailure(errorCode: nil, message: "") == .unknown(detail: ""))
    }
}
