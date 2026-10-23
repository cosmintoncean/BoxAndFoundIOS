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
    /// Everything that holds something, containers included. Only the tag bar
    /// reads it: an item loose in a wardrobe carries tags, and counting only
    /// what is in boxes would leave it out of the bar it belongs in.
    private var places: [Box] = []
    private var searchTerm = ""
    /// The tag being filtered by, if any. Set by tapping it in the bar.
    private var activeTag: String?
    private var isLoading = true
    private var failure: InventoryFailure?

    init(
        userID: String,
        repository: any InventoryReading = Dependencies.inventoryReading,
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
            tags: tagChips,
            content: content
        )
    }

    private var tagChips: [InventoryViewState.TagChip] {
        guard failure == nil else { return [] }
        return Tags.usageCounts(places).map { tag in
            InventoryViewState.TagChip(
                id: tag.label.lowercased(),
                label: tag.label,
                count: tag.count,
                isActive: activeTag?.caseInsensitiveCompare(tag.label) == .orderedSame,
                isDerived: Tags.isDerived(tag.label)
            )
        }
    }

    private var content: InventoryViewState.Content {
        if isLoading { return .loading }
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        if households.isEmpty { return .empty(message: InventoryCopy.noHouseholds) }
        if boxes.isEmpty { return .empty(message: InventoryCopy.noBoxes) }

        // A tag narrows a search rather than replacing it: both are ways of
        // saying "not all of them", and they compose.
        let matches = BoxSearch.filter(boxes, term: searchTerm)
            .filter { Tags.boxHasTag($0.box, tag: activeTag) }
        guard !matches.isEmpty else {
            return .empty(
                message: InventoryCopy.nothingMatches(term: searchTerm.trimmed, tag: activeTag)
            )
        }

        let isSearching = !searchTerm.trimmed.isEmpty
        return .sections(
            BoxSearch.groupByRoom(rooms: rooms, matches: matches).map { group in
                InventoryViewState.RoomSection(
                    // The unassigned group has no room, so no id of its own.
                    id: group.room?.id ?? "unassigned",
                    title: InventoryCopy.roomName(group.room?.name),
                    roomID: group.room?.id,
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

    /// Coming back from a screen that may have written something. Counts, box
    /// names and rooms can all have moved while it was open.
    func refresh() async {
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

    /// Tapping a tag narrows the list to it; tapping it again clears it. One
    /// at a time: two at once asks whether it means both or either, and
    /// neither answer is guessable from a row of chips.
    func tagTapped(_ tag: String) {
        activeTag = activeTag?.caseInsensitiveCompare(tag) == .orderedSame ? nil : tag
    }

    func householdSelected(_ id: String) async {
        guard id != active?.id, let chosen = households.first(where: { $0.id == id }) else { return }
        active = chosen
        activeHousehold.set(chosen.id)
        searchTerm = ""
        // Another household's tags are not this one's.
        activeTag = nil
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
            places = []
        }
    }

    private func loadContents(of household: Household) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            async let rooms = repository.rooms(householdID: household.id)
            async let places = repository.places(householdID: household.id)
            self.rooms = try await rooms
            // One read brings back everything that holds something. The list
            // shows boxes; the tag bar counts the lot, because a tag on an
            // item loose in a wardrobe is still a tag in this household.
            let found = try await places
            self.places = found
            self.boxes = found.filter(Places.isBox)
        } catch {
            failure = InventoryFailure.from(error)
            rooms = []
            boxes = []
            places = []
        }
    }
}
