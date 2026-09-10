import Testing
@testable import BoxAndFound

@Suite("Credential shape checks")
struct CredentialsTests {

    @Test("Accepts ordinary addresses", arguments: [
        "a@b.co", "cosmin.toncean@gmail.com", "first+tag@sub.example.co.uk",
    ])
    func accepts(_ email: String) {
        #expect(Credentials.isEmailShaped(email))
    }

    @Test("Rejects the obvious typos", arguments: [
        "", "no-at-sign", "@example.com", "user@", "user@host", "user@.com",
        "user @example.com", "user@exam ple.com",
    ])
    func rejects(_ email: String) {
        #expect(!Credentials.isEmailShaped(email))
    }

    @Test("Surrounding whitespace is trimmed, not rejected")
    func trims() {
        #expect(Credentials.isEmailShaped("  user@example.com \n"))
        #expect(Credentials.normaliseEmail("  User@Example.com  ") == "User@Example.com")
    }

    @Test("Password length matches Supabase's own minimum")
    func passwordLength() {
        #expect(!Credentials.isPasswordLongEnough("12345"))
        #expect(Credentials.isPasswordLongEnough("123456"))
    }
}
