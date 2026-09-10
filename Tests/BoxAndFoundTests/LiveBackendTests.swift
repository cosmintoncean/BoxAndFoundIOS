import Testing
@testable import BoxAndFound

/// The one test that talks to the real Supabase project.
///
/// Everything else in this suite folder is pure. This exists because the
/// expensive mistakes in a client like this are not logic errors — they are a
/// wrong URL, a stale anon key, an SDK call shaped wrong, or a GoTrue error
/// code that has been renamed since the mapping was written. None of those
/// show up in a unit test, and none of them can be caught by eye from a
/// machine with no simulator.
///
/// One deliberately failing sign-in proves all four at once: reaching the
/// project, being accepted as a client, getting a structured error back, and
/// mapping it to the case the screen expects.
///
/// Skipped automatically when the build has CI's placeholder credentials, so a
/// pull request from a fork — which Actions never gives secrets to — still
/// goes green.
@Suite("Live backend", .enabled(if: AppConfig.isLiveBackendConfigured))
struct LiveBackendTests {

    @Test("A wrong password comes back as invalid credentials, not as noise")
    func wrongPasswordIsMapped() async {
        let repository = AuthRepository()
        do {
            try await repository.signIn(
                email: "ci-no-such-account@boxandfound.net",
                password: "not-the-password-\(UUID().uuidString)"
            )
            Issue.record("Signing in with a made-up account somehow succeeded")
        } catch {
            // .network would mean the URL or connectivity is wrong; .unknown
            // would mean GoTrue said something the mapping has never seen.
            // Either is worth failing over.
            #expect(error == .invalidCredentials)
        }
    }
}
