import Foundation
import Observation

/// Where in the tree a storage screen is standing.
///
/// A room and a container are different starting points for the same screen: a
/// room's level is everything with no container above it, a container's level
/// is everything that names it as parent. Carrying which one it is, rather
/// than two optional ids, is what stops the presenter guessing.
enum StorageTarget: Equatable, Hashable {
    /// The room's own top level. The name is carried so the title can be drawn
    /// before anything has loaded.
    case room(id: String, name: String)
    case container(id: String)
}

/// One level of storage: what is in this room, or in this container.
@MainActor
@Observable
final class StoragePresenter: Presenter {

    private let target: StorageTarget
    private let householdID: String
    private let repository: any InventoryReading
    private let writes: any InventoryWriting

    private var places: [Box] = []
    private var rooms: [Room] = []
    private var isLoading = true
    private var failure: InventoryFailure?

    private var containerDraft: Draft?
    private var itemDraft: ItemDraft?
    private var pendingDelete: String?
    /// A write that failed, said where it was attempted rather than over the
    /// whole screen: a refused create must not look like a household that
    /// would not load.
    private var writeFailure: InventoryFailure?

    /// The container being made. Held here rather than in the view so the
    /// rules about it — a name is required, a type is always one of ours —
    /// are testable.
    private struct Draft: Equatable {
        var name = ""
        var type = Places.containerTypes.first ?? "other"
        var isSaving = false
    }

    private struct ItemDraft: Equatable {
        var name = ""
        var quantity = 1
        var isSaving = false
    }

    init(
        target: StorageTarget,
        householdID: String,
        repository: any InventoryReading = Dependencies.inventoryReading,
        writes: any InventoryWriting = Dependencies.inventoryWriting
    ) {
        self.target = target
        self.householdID = householdID
        self.repository = repository
        self.writes = writes
    }

    // MARK: - What the view draws

    var viewState: StorageViewState {
        StorageViewState(
            title: title,
            content: content,
            canAddContainer: !isAtTheDepthLimit,
            containerDraft: containerDraft.map {
                StorageViewState.ContainerDraft(
                    name: $0.name,
                    type: $0.type,
                    types: Places.containerTypes.map { type in
                        StorageViewState.TypeOption(
                            id: type,
                            label: ContainerLook.label(for: type),
                            symbol: ContainerLook.symbol(for: type)
                        )
                    },
                    // A container with no name cannot be told from the next
                    // one in a list sorted by name.
                    canSave: !$0.name.trimmed.isEmpty && !$0.isSaving,
                    isSaving: $0.isSaving,
                    errorMessage: writeFailure.map(InventoryCopy.message(for:))
                )
            },
            itemDraft: itemDraft.map {
                StorageViewState.ItemDraft(
                    name: $0.name,
                    quantity: $0.quantity,
                    canSave: !$0.name.trimmed.isEmpty && !$0.isSaving,
                    isSaving: $0.isSaving,
                    errorMessage: writeFailure.map(InventoryCopy.message(for:))
                )
            },
            deletePrompt: pendingDelete.flatMap { id in
                guard let container = places.first(where: { $0.id == id }) else { return nil }
                return StorageViewState.DeletePrompt(
                    id: id,
                    title: StorageCopy.deleteTitle,
                    message: StorageCopy.deleteMessage(
                        name: InventoryCopy.boxName(container.name),
                        contents: Places.contents(of: container, in: places)
                    )
                )
            }
        )
    }

    private var isAtTheDepthLimit: Bool {
        Places.depth(of: container, index: Places.index(places)) >= Places.maxDepth - 1
    }

    private var title: String {
        switch target {
        case .room(_, let name):
            InventoryCopy.roomName(name)
        case .container:
            InventoryCopy.boxName(container?.name)
        }
    }

    private var content: StorageViewState.Content {
        if isLoading { return .loading }
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }

        let index = Places.index(places)
        let here = container
        let roomID = here?.roomID ?? target.roomID
        let children = Places.children(places, parentID: here?.id, roomID: roomID)
        let containers = children.filter(Places.isContainer).sorted(by: byName)
        let boxes = children.filter(Places.isBox).sorted(by: byName)

        // A room keeps its own loose items in a hidden place of its own; a
        // container keeps them on itself.
        let holder = here ?? Places.roomItemsHolder(in: places, roomID: roomID)
        let loose = Places.looseItems(of: holder)

        let isEmpty = containers.isEmpty && boxes.isEmpty && loose.isEmpty
        let depth = Places.depth(of: here, index: index)

        return .contents(
            StorageViewState.Contents(
                path: here.map {
                    // The last step is this screen's own title, so it would
                    // only repeat itself.
                    Array(
                        Places.path(
                            of: $0,
                            index: index,
                            rooms: rooms,
                            unnamed: InventoryCopy.boxName(nil)
                        ).dropLast()
                    )
                } ?? [],
                containers: containers.map(row(for:)),
                boxes: boxes.map(row(for:)),
                looseItems: loose.map(looseRow(for:)),
                emptyMessage: isEmpty ? emptyMessage : nil,
                // Said at the last level that can still hold something, not
                // after the server has refused: the message belongs before the
                // attempt.
                depthNote: depth >= Places.maxDepth - 1
                    ? StorageCopy.tooDeep(limit: Places.maxDepth)
                    : nil

            )
        )
    }

    private var container: Box? {
        guard case .container(let id) = target else { return nil }
        return places.first { $0.id == id }
    }

    private var emptyMessage: String {
        switch target {
        case .room: StorageCopy.emptyRoom
        case .container: StorageCopy.emptyContainer
        }
    }

    private func byName(_ lhs: Box, _ rhs: Box) -> Bool {
        InventorySort.key(lhs.name) < InventorySort.key(rhs.name)
    }

    private func row(for place: Box) -> StorageViewState.PlaceRow {
        let isContainer = Places.isContainer(place)
        let name = InventoryCopy.boxName(place.name)
        let kind = ContainerLook.label(for: place.type)
        return StorageViewState.PlaceRow(
            id: place.id,
            name: name,
            symbol: isContainer
                ? ContainerLook.symbol(for: place.type)
                : BoxSymbols.symbol(forIconKey: place.icon),
            // Most people call a wardrobe "Wardrobe", and a row that reads
            // "Wardrobe / Wardrobe · 1 box" says the word twice to no end.
            kindLabel: isContainer && kind.caseInsensitiveCompare(name) != .orderedSame
                ? kind
                : nil,
            detail: isContainer
                ? StorageCopy.contents(Places.contents(of: place, in: places))
                : InventoryCopy.itemCount(place.items.count),
            isContainer: isContainer
        )
    }

    private func looseRow(for item: BoxItem) -> StorageViewState.LooseItemRow {
        StorageViewState.LooseItemRow(
            id: item.id,
            name: InventoryCopy.itemName(item.name),
            quantity: StorageCopy.quantity(item.quantity),
            isTaken: item.isTaken,
            tags: Tags.normalise(item.tags)
        )
    }

    // MARK: - Intents

    func appeared() async {
        guard places.isEmpty else { return }
        await reload()
    }

    func retryTapped() async {
        await reload()
    }

    /// Coming back from a screen that may have written something.
    func refresh() async {
        await reload()
    }

    // MARK: - Making a container

    func newContainerTapped() {
        writeFailure = nil
        containerDraft = Draft()
    }

    func containerNameChanged(_ name: String) { containerDraft?.name = name }

    func containerTypeChanged(_ type: String) { containerDraft?.type = type }

    func dismissContainerDraft() { containerDraft = nil }

    func createContainerTapped() async {
        guard let draft = containerDraft, !draft.name.trimmed.isEmpty, !draft.isSaving else {
            return
        }
        containerDraft?.isSaving = true
        do {
            _ = try await writes.createContainer(
                householdID: householdID,
                name: draft.name.trimmed,
                type: draft.type,
                // A room is sent only at a room's own level. Inside a
                // container the server resolves the room from the parent.
                roomID: container == nil ? target.roomID : nil,
                parentID: container?.id
            )
            containerDraft = nil
            await reload()
        } catch {
            writeFailure = InventoryFailure.from(error)
            containerDraft?.isSaving = false
        }
    }

    // MARK: - Putting something here that is not in a box

    func newItemTapped() {
        writeFailure = nil
        itemDraft = ItemDraft()
    }

    func itemNameChanged(_ name: String) { itemDraft?.name = name }

    func itemQuantityChanged(_ quantity: Int) {
        itemDraft?.quantity = max(1, min(quantity, 999))
    }

    func dismissItemDraft() { itemDraft = nil }

    func addItemTapped() async {
        guard let draft = itemDraft, !draft.name.trimmed.isEmpty, !draft.isSaving else { return }
        itemDraft?.isSaving = true
        do {
            guard let holderID = try await holder() else {
                itemDraft?.isSaving = false
                return
            }
            let existing = places.first { $0.id == holderID }?.items ?? []
            try await writes.applyItemPlan(
                boxID: holderID,
                plan: ItemSyncPlan(
                    inserts: [
                        ItemInsert(
                            name: draft.name.trimmed,
                            quantity: draft.quantity,
                            position: ItemSync.nextPosition(after: existing),
                            isTaken: false,
                            takenAt: nil,
                            takenBy: nil
                        ),
                    ]
                )
            )
            itemDraft = nil
            await reload()
        } catch {
            writeFailure = InventoryFailure.from(error)
            itemDraft?.isSaving = false
        }
    }

    /// What an item put here hangs off.
    ///
    /// A container holds its own. A room cannot — it is not a place and has no
    /// id for `box_items.box_id` to point at — so it keeps a nameless
    /// stand-in, made on the first thing put in the room and never shown.
    private func holder() async throws(InventoryFailure) -> String? {
        if let container { return container.id }
        guard let roomID = target.roomID else { return nil }
        if let existing = Places.roomItemsHolder(in: places, roomID: roomID) {
            return existing.id
        }
        return try await writes.createContainer(
            householdID: householdID,
            name: "",
            type: Places.typeRoomItems,
            roomID: roomID,
            parentID: nil
        ).id
    }

    // MARK: - Removing a container

    func deleteTapped(id: String) { pendingDelete = id }

    func dismissDelete() { pendingDelete = nil }

    func confirmDeleteTapped() async {
        guard let id = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await writes.deleteContainer(id: id)
            await reload()
        } catch {
            // Nothing is open to show this in, and the list is what the
            // delete was about, so here it does belong over the screen.
            failure = InventoryFailure.from(error)
        }
    }

    private func reload() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            async let places = repository.places(householdID: householdID)
            async let rooms = repository.rooms(householdID: householdID)
            self.places = try await places
            self.rooms = try await rooms
        } catch {
            failure = InventoryFailure.from(error)
            places = []
            rooms = []
        }
    }
}

private extension StorageTarget {
    var roomID: String? {
        switch self {
        case .room(let id, _): id
        case .container: nil
        }
    }
}
