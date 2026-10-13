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

    private var places: [Box] = []
    private var rooms: [Room] = []
    private var isLoading = true
    private var failure: InventoryFailure?

    init(
        target: StorageTarget,
        householdID: String,
        repository: any InventoryReading = Dependencies.inventoryReading
    ) {
        self.target = target
        self.householdID = householdID
        self.repository = repository
    }

    // MARK: - What the view draws

    var viewState: StorageViewState {
        StorageViewState(title: title, content: content)
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
        return StorageViewState.PlaceRow(
            id: place.id,
            name: InventoryCopy.boxName(place.name),
            symbol: isContainer
                ? ContainerLook.symbol(for: place.type)
                : BoxSymbols.symbol(forIconKey: place.icon),
            kindLabel: isContainer ? ContainerLook.label(for: place.type) : nil,
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
