import Foundation
import Testing
@testable import BoxAndFound

private final class StubHouseholds: HouseholdManaging, @unchecked Sendable {
    var created: [(name: String, ownerID: String)] = []
    var joined: [(householdID: String, userID: String)] = []
    var left: [(householdID: String, userID: String)] = []
    var deleted: [String] = []
    var rotated: [String] = []
    var preview: InvitePreview?
    var failure: HouseholdFailure?

    func create(name: String, ownerID: String) async throws(HouseholdFailure) -> Household {
        if let failure { throw failure }
        created.append((name, ownerID))
        return Household(id: "new-household", name: name, inviteCode: "NEW123", ownerID: ownerID)
    }

    func rename(householdID: String, name: String) async throws(HouseholdFailure) {}

    func regenerateInviteCode(householdID: String) async throws(HouseholdFailure) -> String {
        if let failure { throw failure }
        rotated.append(householdID)
        return "ROT123"
    }

    func previewInvite(code: String) async throws(HouseholdFailure) -> InvitePreview {
        if let failure { throw failure }
        guard let preview else { throw HouseholdFailure.unknownInviteCode }
        return preview
    }

    func join(householdID: String, userID: String) async throws(HouseholdFailure) {
        if let failure { throw failure }
        joined.append((householdID, userID))
    }

    func leave(householdID: String, userID: String) async throws(HouseholdFailure) {
        if let failure { throw failure }
        left.append((householdID, userID))
    }

    func members(householdID: String) async throws(HouseholdFailure) -> [HouseholdMember] { [] }

    func delete(householdID: String) async throws(HouseholdFailure) {
        if let failure { throw failure }
        deleted.append(householdID)
    }
}

private struct StubReader: InventoryReading {
    var all: [Household] = []
    func households(userID: String) async throws(InventoryFailure) -> [Household] { all }
    func rooms(householdID: String) async throws(InventoryFailure) -> [Room] { [] }
    func boxes(householdID: String) async throws(InventoryFailure) -> [Box] { [] }
    func box(id: String) async throws(InventoryFailure) -> Box { throw InventoryFailure.notFound }
}

@Suite("Households")
@MainActor
struct HouseholdsPresenterTests {

    private let site = "https://boxandfound.net"

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    private func makePresenter(
        owned: [Household] = [],
        households: StubHouseholds = StubHouseholds(),
        store: ActiveHouseholdStore? = nil
    ) -> HouseholdsPresenter {
        HouseholdsPresenter(
            userID: "user-1",
            reader: StubReader(all: owned),
            households: households,
            activeHousehold: store ?? ActiveHouseholdStore(defaults: defaults()),
            siteURL: site
        )
    }

    private func owned(_ id: String, _ name: String, code: String? = "ABC123") -> Household {
        Household(id: id, name: name, inviteCode: code, ownerID: "user-1")
    }

    private func joined(_ id: String, _ name: String) -> Household {
        Household(id: id, name: name, inviteCode: "SOMEBODY", ownerID: "someone-else")
    }

    // MARK: - Rows

    @Test("An owner sees the code and a link; a member sees neither")
    func rolesDecideWhatIsShown() async {
        let presenter = makePresenter(owned: [owned("h1", "Home"), joined("h2", "Studio")])
        await presenter.appeared()

        let rows = presenter.viewState.rows
        #expect(rows.map(\.roleNote) == [HouseholdCopy.owner, HouseholdCopy.member])

        #expect(rows[0].inviteCode == "ABC123")
        #expect(rows[0].canDelete)
        #expect(!rows[0].canLeave)

        // A member cannot rotate a code, so showing them one would only invite
        // them to share a link they could never revoke.
        #expect(rows[1].inviteCode == nil)
        #expect(rows[1].shareURL == nil)
        #expect(rows[1].canLeave)
        #expect(!rows[1].canDelete)
    }

    @Test("The share link is the one the web client would build")
    func shareLinkRoundTrips() async {
        let presenter = makePresenter(owned: [owned("h1", "The Flat")])
        await presenter.appeared()

        let share = presenter.viewState.rows[0].shareURL
        #expect(share == "https://boxandfound.net/?invite=ABC123&name=The%20Flat")
        #expect(InviteLink.parse(share) == .invite(code: "ABC123", householdName: "The Flat"))
    }

    @Test("No households says so rather than showing an empty list")
    func emptyState() async {
        let presenter = makePresenter()
        await presenter.appeared()
        #expect(presenter.viewState.emptyMessage == HouseholdCopy.noHouseholds)
    }

    // MARK: - Creating

    @Test("Creating needs a name, and opens what it made")
    func creating() async {
        let store = ActiveHouseholdStore(defaults: defaults())
        let stub = StubHouseholds()
        let presenter = makePresenter(households: stub, store: store)
        await presenter.appeared()

        #expect(!presenter.viewState.isCreateEnabled)
        presenter.newHouseholdNameChanged("  ")
        #expect(!presenter.viewState.isCreateEnabled)

        presenter.newHouseholdNameChanged("Studio")
        #expect(presenter.viewState.isCreateEnabled)

        await presenter.createTapped()
        #expect(stub.created.map(\.name) == ["Studio"])
        #expect(store.activeHouseholdID == "new-household")
        #expect(presenter.viewState.newHouseholdName.isEmpty)
    }

    // MARK: - Joining

    @Test("A half-typed code is not worth a round trip")
    func joinGating() async {
        let presenter = makePresenter()
        await presenter.appeared()

        presenter.joinCodeChanged("ABC")
        #expect(!presenter.viewState.isJoinEnabled)

        presenter.joinCodeChanged("abc123")
        #expect(presenter.viewState.isJoinEnabled)
    }

    @Test("A looked-up invite says what is being joined before anyone joins it")
    func previewBeforeJoining() async {
        let stub = StubHouseholds()
        stub.preview = InvitePreview(
            householdID: "h9",
            householdName: "The Flat",
            ownerName: "Cosmin",
            memberCount: 3,
            isAlreadyMember: false
        )
        let presenter = makePresenter(households: stub)
        await presenter.appeared()

        presenter.joinCodeChanged("ABC123")
        await presenter.previewTapped()

        let card = presenter.viewState.invite
        #expect(card?.title == "Join The Flat?")
        #expect(card?.detail == "3 members · invited by Cosmin")
        #expect(card?.canAccept == true)
        // Looking is not joining.
        #expect(stub.joined.isEmpty)
    }

    @Test("Accepting joins, opens it, and says so")
    func accepting() async {
        let store = ActiveHouseholdStore(defaults: defaults())
        let stub = StubHouseholds()
        stub.preview = InvitePreview(
            householdID: "h9", householdName: "The Flat", ownerName: nil,
            memberCount: 1, isAlreadyMember: false
        )
        let presenter = makePresenter(households: stub, store: store)
        await presenter.appeared()

        presenter.joinCodeChanged("ABC123")
        await presenter.previewTapped()
        await presenter.acceptTapped()

        #expect(stub.joined.map(\.householdID) == ["h9"])
        #expect(store.activeHouseholdID == "h9")
        #expect(presenter.viewState.invite == nil)
        #expect(presenter.viewState.notice?.kind == .success)
    }

    @Test("An invite you have already accepted offers nothing to accept")
    func alreadyAMember() async {
        let stub = StubHouseholds()
        stub.preview = InvitePreview(
            householdID: "h9", householdName: "Home", ownerName: nil,
            memberCount: 2, isAlreadyMember: true
        )
        let presenter = makePresenter(households: stub)
        await presenter.appeared()

        presenter.joinCodeChanged("ABC123")
        await presenter.previewTapped()

        #expect(presenter.viewState.invite?.canAccept == false)
        #expect(presenter.viewState.invite?.acceptTitle == "You are already a member")

        await presenter.acceptTapped()
        #expect(stub.joined.isEmpty)
    }

    @Test("A code that matches nothing says so in its own words")
    func unknownCode() async {
        let presenter = makePresenter(households: StubHouseholds())
        await presenter.appeared()

        presenter.joinCodeChanged("ZZZ999")
        await presenter.previewTapped()

        #expect(presenter.viewState.invite == nil)
        #expect(presenter.viewState.notice?.text == HouseholdCopy.message(for: .unknownInviteCode))
    }

    @Test("An invite arriving as a link is looked up without being typed")
    func inviteFromALink() async {
        let stub = StubHouseholds()
        stub.preview = InvitePreview(
            householdID: "h9", householdName: "The Flat", ownerName: nil,
            memberCount: 1, isAlreadyMember: false
        )
        let presenter = makePresenter(households: stub)
        await presenter.appeared()

        await presenter.inviteArrived(code: "abc123")

        #expect(presenter.viewState.joinCode == "ABC123")
        #expect(presenter.viewState.invite?.title == "Join The Flat?")
    }

    @Test("Retyping the code drops the card that was about to be wrong")
    func retypingClearsTheCard() async {
        let stub = StubHouseholds()
        stub.preview = InvitePreview(
            householdID: "h9", householdName: "The Flat", ownerName: nil,
            memberCount: 1, isAlreadyMember: false
        )
        let presenter = makePresenter(households: stub)
        await presenter.appeared()
        presenter.joinCodeChanged("ABC123")
        await presenter.previewTapped()
        #expect(presenter.viewState.invite != nil)

        presenter.joinCodeChanged("ABC124")
        #expect(presenter.viewState.invite == nil)
    }

    // MARK: - Leaving and deleting

    /// Leaving the household you had open must not leave the inventory
    /// pointing at one you can no longer read.
    @Test("Leaving the open household forgets it")
    func leavingForgetsTheActiveOne() async {
        let store = ActiveHouseholdStore(defaults: defaults())
        store.set("h2")
        let stub = StubHouseholds()
        let presenter = makePresenter(owned: [joined("h2", "Studio")], households: stub, store: store)
        await presenter.appeared()

        await presenter.leaveTapped("h2")

        #expect(stub.left.map(\.householdID) == ["h2"])
        #expect(store.activeHouseholdID == nil)
    }

    @Test("Leaving a different household leaves the open one alone")
    func leavingAnotherKeepsTheActiveOne() async {
        let store = ActiveHouseholdStore(defaults: defaults())
        store.set("h1")
        let presenter = makePresenter(
            owned: [owned("h1", "Home"), joined("h2", "Studio")],
            store: store
        )
        await presenter.appeared()

        await presenter.leaveTapped("h2")
        #expect(store.activeHouseholdID == "h1")
    }

    @Test("Deleting removes it and forgets it")
    func deleting() async {
        let store = ActiveHouseholdStore(defaults: defaults())
        store.set("h1")
        let stub = StubHouseholds()
        let presenter = makePresenter(owned: [owned("h1", "Home")], households: stub, store: store)
        await presenter.appeared()

        await presenter.deleteTapped("h1")

        #expect(stub.deleted == ["h1"])
        #expect(store.activeHouseholdID == nil)
    }

    /// The project, not the person, is at fault — and the person reading it is
    /// the one who can run the migration.
    @Test("A project missing delete_household is told which migration to run")
    func missingDeleteFunction() async {
        let stub = StubHouseholds()
        stub.failure = .deleteFunctionMissing
        let presenter = makePresenter(owned: [owned("h1", "Home")], households: stub)
        await presenter.appeared()

        await presenter.deleteTapped("h1")

        #expect(presenter.viewState.notice?.text.contains("MIGRATION_delete_household_fn.sql") == true)
    }

    @Test("Rotating the code warns that the old link has stopped working")
    func rotating() async {
        let stub = StubHouseholds()
        let presenter = makePresenter(owned: [owned("h1", "Home")], households: stub)
        await presenter.appeared()

        await presenter.rotateCodeTapped("h1")

        #expect(stub.rotated == ["h1"])
        #expect(presenter.viewState.notice?.text == HouseholdCopy.codeRotated)
    }
}
