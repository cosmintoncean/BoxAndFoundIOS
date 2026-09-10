import Foundation
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
        } catch let failure as AuthFailure {
            // .network would mean the URL or connectivity is wrong; .unknown
            // would mean GoTrue said something the mapping has never seen.
            // Either is worth failing over.
            #expect(failure == .invalidCredentials)
        } catch {
            // Typed throws does not always narrow the catch binding, so this
            // arm is reachable in principle. Anything landing here is a
            // failure the repository was supposed to have mapped.
            Issue.record("Unmapped error escaped AuthRepository: \(error)")
        }
    }

    // MARK: - Query shapes
    //
    // These run unauthenticated, so row-level security answers every one of
    // them with nothing. That is the point: emptiness is not what is being
    // checked. PostgREST rejects a projection it cannot parse — an embedded
    // table that is not a real relationship, a column that does not exist —
    // with a 400 rather than an empty list, so a query that comes back at all
    // is a query the server understood.
    //
    // It is the check the Android client did by hand before trusting the
    // screens behind sign-in, written down so it runs on every push instead.
    //
    // The ids are random UUIDs rather than plausible strings: `household_id`
    // and `owner_id` are uuid columns, and a non-uuid would be rejected for
    // its shape, which would look exactly like the failure this is hunting.

    private var absentID: String { UUID().uuidString }

    @Test("The households pair — owned, plus joined through the membership table")
    func householdsQueryShape() async {
        await expectAccepted("households") {
            _ = try await InventoryRepository().households(userID: absentID)
        }
    }

    @Test("Rooms by household")
    func roomsQueryShape() async {
        await expectAccepted("rooms") {
            _ = try await InventoryRepository().rooms(householdID: absentID)
        }
    }

    /// The one most likely to be wrong: `box_items` has to be a relationship
    /// PostgREST can resolve, and every column named in it has to exist.
    @Test("Boxes with their items embedded in one round trip")
    func boxesQueryShape() async {
        await expectAccepted("boxes with embedded box_items") {
            _ = try await InventoryRepository().boxes(householdID: absentID)
        }
    }

    /// Also confirms the PGRST116 mapping against the real server rather than
    /// against a guess about what PostgREST calls "no rows".
    @Test("A box id that is not there reads as missing, not as broken")
    func singleBoxQueryShape() async {
        do {
            _ = try await InventoryRepository().box(id: absentID)
            Issue.record("A random box id somehow returned a box")
        } catch let failure as InventoryFailure {
            #expect(failure == .notFound)
        } catch {
            Issue.record("Unmapped error escaped InventoryRepository: \(error)")
        }
    }

    private func expectAccepted(
        _ what: String,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
        } catch {
            // The detail matters here — "Could not find a relationship" and
            // "permission denied for table" are very different problems.
            Issue.record("PostgREST rejected the \(what) query: \(error)")
        }
    }
}
