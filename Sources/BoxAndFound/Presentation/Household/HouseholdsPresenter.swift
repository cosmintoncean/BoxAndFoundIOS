import Foundation
import Observation

/// Drives the households screen: what you are in, what you can join, and what
/// you can hand to someone else.
@MainActor
@Observable
final class HouseholdsPresenter: Presenter {

    private let userID: String
    private let reader: any InventoryReading
    private let households: any HouseholdManaging
    private let activeHousehold: ActiveHouseholdStore
    private let siteURL: String

    private var rows: [Household] = []
    private var isLoading = true
    private var isBusy = false
    private var notice: HouseholdsViewState.Notice?

    private var newHouseholdName = ""
    private var joinCode = ""
    private var preview: InvitePreview?

    init(
        userID: String,
        reader: any InventoryReading = Dependencies.inventoryReading,
        households: any HouseholdManaging = Dependencies.householdManaging,
        activeHousehold: ActiveHouseholdStore = ActiveHouseholdStore(),
        siteURL: String = AppConfig.siteURL
    ) {
        self.userID = userID
        self.reader = reader
        self.households = households
        self.activeHousehold = activeHousehold
        self.siteURL = siteURL
    }

    // MARK: - What the view draws

    var viewState: HouseholdsViewState {
        HouseholdsViewState(
            isLoading: isLoading,
            rows: rows.map(row),
            emptyMessage: !isLoading && rows.isEmpty ? HouseholdCopy.noHouseholds : nil,
            newHouseholdName: newHouseholdName,
            isCreateEnabled: !isBusy && !newHouseholdName.trimmed.isEmpty,
            joinCode: joinCode,
            // A round trip for a half-typed code would fail every keystroke.
            isJoinEnabled: !isBusy && InviteCode.isPlausible(joinCode),
            invite: inviteCard,
            isBusy: isBusy,
            notice: notice
        )
    }

    private func row(_ household: Household) -> HouseholdsViewState.Row {
        let isOwner = household.isOwned(by: userID)
        return HouseholdsViewState.Row(
            id: household.id,
            name: InventoryCopy.householdName(household.name),
            roleNote: isOwner ? HouseholdCopy.owner : HouseholdCopy.member,
            isActive: household.id == activeHousehold.activeHouseholdID,
            // A member cannot rotate a code, so showing them one would only
            // invite them to share a link they cannot revoke.
            inviteCode: isOwner ? household.inviteCode : nil,
            shareURL: isOwner ? household.inviteCode.map {
                InviteLink.inviteURL(code: $0, householdName: household.name, siteURL: siteURL)
            } : nil,
            canDelete: isOwner,
            canLeave: !isOwner
        )
    }

    private var inviteCard: HouseholdsViewState.InviteCard? {
        guard let preview else { return nil }
        return HouseholdsViewState.InviteCard(
            title: HouseholdCopy.inviteTitle(preview.householdName),
            detail: HouseholdCopy.inviteDetail(
                memberCount: preview.memberCount,
                ownerName: preview.ownerName
            ),
            acceptTitle: HouseholdCopy.acceptTitle(isAlreadyMember: preview.isAlreadyMember),
            canAccept: !preview.isAlreadyMember && !isBusy
        )
    }

    // MARK: - Intents

    func appeared() async {
        guard rows.isEmpty else { return }
        await reload()
    }

    func newHouseholdNameChanged(_ value: String) { newHouseholdName = value }

    func joinCodeChanged(_ value: String) {
        joinCode = value
        // A code being retyped means the card on screen is about to be wrong.
        preview = nil
    }

    func createTapped() async {
        guard !isBusy, !newHouseholdName.trimmed.isEmpty else { return }
        await perform {
            let created = try await self.households.create(
                name: self.newHouseholdName,
                ownerID: self.userID
            )
            self.newHouseholdName = ""
            // A household you just made is the one you want open.
            self.activeHousehold.set(created.id)
            await self.reload()
        }
    }

    /// Looks the code up without joining, so what is being accepted is on
    /// screen before anyone accepts it.
    func previewTapped() async {
        guard !isBusy, InviteCode.isPlausible(joinCode) else { return }
        await perform {
            self.preview = try await self.households.previewInvite(code: self.joinCode)
        }
    }

    /// An invite that arrived as a link rather than as typed characters.
    ///
    /// The link carries a household name too, and it is ignored on purpose:
    /// the preview comes back with the real one, and a name from a URL is
    /// whatever the sender pasted.
    func inviteArrived(code: String) async {
        joinCode = InviteCode.normalise(code)
        await previewTapped()
    }

    func acceptTapped() async {
        guard let preview, !preview.isAlreadyMember, !isBusy else { return }
        await perform {
            try await self.households.join(householdID: preview.householdID, userID: self.userID)
            self.preview = nil
            self.joinCode = ""
            self.activeHousehold.set(preview.householdID)
            await self.reload()
            self.notice = .init(kind: .success, text: HouseholdCopy.joined(preview.householdName))
        }
    }

    func dismissInviteTapped() {
        preview = nil
        joinCode = ""
    }

    func leaveTapped(_ householdID: String) async {
        guard !isBusy else { return }
        await perform {
            try await self.households.leave(householdID: householdID, userID: self.userID)
            self.forgetIfActive(householdID)
            await self.reload()
            self.notice = .init(kind: .success, text: HouseholdCopy.left)
        }
    }

    func deleteTapped(_ householdID: String) async {
        guard !isBusy else { return }
        await perform {
            try await self.households.delete(householdID: householdID)
            self.forgetIfActive(householdID)
            await self.reload()
            self.notice = .init(kind: .success, text: HouseholdCopy.deleted)
        }
    }

    func rotateCodeTapped(_ householdID: String) async {
        guard !isBusy else { return }
        await perform {
            _ = try await self.households.regenerateInviteCode(householdID: householdID)
            await self.reload()
            self.notice = .init(kind: .success, text: HouseholdCopy.codeRotated)
        }
    }

    // MARK: -

    /// Leaving or deleting the household you had open must not leave the
    /// inventory pointing at one you can no longer read.
    private func forgetIfActive(_ householdID: String) {
        if activeHousehold.activeHouseholdID == householdID {
            activeHousehold.clear()
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await reader.households(userID: userID)
        } catch {
            // This one read belongs to the inventory, so it fails in the
            // inventory's words rather than being translated twice.
            let text = (error as? InventoryFailure).map(InventoryCopy.message(for:))
                ?? HouseholdCopy.message(for: HouseholdFailure.from(error))
            notice = .init(kind: .error, text: text)
        }
    }

    private func perform(_ block: @MainActor () async throws -> Void) async {
        isBusy = true
        notice = nil
        defer { isBusy = false }
        do {
            try await block()
        } catch {
            notice = .init(kind: .error, text: HouseholdCopy.message(for: HouseholdFailure.from(error)))
        }
    }
}
