import Foundation
import Observation

/// Drives the box list: which household is open, what is being searched for,
/// and what came back.
@MainActor
@Observable
final class InventoryPresenter: Presenter {

    private let userID: String
    private let repository: any InventoryReading
    private let activeHousehold: ActiveHouseholdStore
    /// Sign-out belongs to the session, which this screen does not own. Taking
    /// it as a closure keeps the action an intent on the presenter rather than
    /// a callback the view has to remember to wire up.
    private let signOut: @MainActor () async -> Void

    private var households: [Household] = []
    private var active: Household?
    private var rooms: [Room] = []
    private var boxes: [Box] = []
    private var searchTerm = ""
    private var isLoading = true
    private var failure: InventoryFailure?

    init(
        userID: String,
        repository: any InventoryReading = InventoryRepository(),
        activeHousehold: ActiveHouseholdStore = ActiveHouseholdStore(),
        signOut: @escaping @MainActor () async -> Void = {}
    ) {
        self.userID = userID
        self.repository = repository
        self.activeHousehold = activeHousehold
        self.signOut = signOut
    }

    // MARK: - What the view draws

    var viewState: InventoryViewState {
        InventoryViewState(
            title: InventoryCopy.householdName(active?.name),
            households: households.map {
                .init(id: $0.id, name: InventoryCopy.householdName($0.name))
            },
            activeHouseholdID: active?.id,
            isHouseholdSwitcherVisible: households.count > 1,
            searchTerm: searchTerm,
            // Nothing to search in an empty or broken household, and a search
            // field over an error message is just clutter.
            isSearchVisible: !boxes.isEmpty && failure == nil,
            content: content
        )
    }

    private var content: InventoryViewState.Content {
        if isLoading { return .loading }
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        if households.isEmpty { return .empty(message: InventoryCopy.noHouseholds) }
        if boxes.isEmpty { return .empty(message: InventoryCopy.noBoxes) }

        let matches = BoxSearch.filter(boxes, term: searchTerm)
        guard !matches.isEmpty else {
            return .empty(message: InventoryCopy.noResults(for: searchTerm.trimmed))
        }

        let isSearching = !searchTerm.trimmed.isEmpty
        return .sections(
            BoxSearch.groupByRoom(rooms: rooms, matches: matches).map { group in
                InventoryViewState.RoomSection(
                    // The unassigned group has no room, so no id of its own.
                    id: group.room?.id ?? "unassigned",
                    title: InventoryCopy.roomName(group.room?.name),
                    boxes: group.matches.map { row(for: $0, isSearching: isSearching) }
                )
            }
        )
    }

    private func row(for match: BoxMatch, isSearching: Bool) -> InventoryViewState.BoxRow {
        let box = match.box
        return InventoryViewState.BoxRow(
            id: box.id,
            name: InventoryCopy.boxName(box.name),
            symbol: BoxSymbols.symbol(forIconKey: box.icon),
            location: box.location?.isEmpty == false ? box.location : nil,
            itemCount: InventoryCopy.itemCount(box.items.count),
            takenNote: InventoryCopy.takenNote(box.items.filter(\.isTaken).count),
            // Only worth saying when the box's own name does not explain the
            // hit — otherwise every result repeats itself.
            matchNote: isSearching && !match.nameMatched
                ? InventoryCopy.matchNote(itemNames: match.matchingItems.compactMap(\.name))
                : nil
        )
    }

    // MARK: - Intents

    func appeared() async {
        guard households.isEmpty else { return }
        await reload()
    }

    func retryTapped() async {
        await reload()
    }

    func signOutTapped() async {
        // The remembered household is one account's, not the next one's.
        activeHousehold.clear()
        await signOut()
    }

    func searchChanged(_ term: String) {
        searchTerm = term
    }

    func householdSelected(_ id: String) async {
        guard id != active?.id, let chosen = households.first(where: { $0.id == id }) else { return }
        active = chosen
        activeHousehold.set(chosen.id)
        searchTerm = ""
        await loadContents(of: chosen)
    }

    // MARK: -

    private func reload() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let found = try await repository.households(userID: userID)
            households = found
            // The remembered id is validated against what came back, so being
            // removed from a household cannot strand you on it.
            active = activeHousehold.resolve(from: found)
            if let active {
                activeHousehold.set(active.id)
                await loadContents(of: active)
            } else {
                rooms = []
                boxes = []
            }
        } catch {
            failure = InventoryFailure.from(error)
            rooms = []
            boxes = []
        }
    }

    private func loadContents(of household: Household) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            async let rooms = repository.rooms(householdID: household.id)
            async let boxes = repository.boxes(householdID: household.id)
            self.rooms = try await rooms
            self.boxes = try await boxes
        } catch {
            failure = InventoryFailure.from(error)
            rooms = []
            boxes = []
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
