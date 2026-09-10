import Foundation
import Observation

/// Drives one box: what is in it, what is out, and taking or returning it.
@MainActor
@Observable
final class BoxDetailPresenter: Presenter {

    private let boxID: String
    private let userID: String
    private let reader: any InventoryReading
    private let writer: any InventoryWriting
    private let imageURLs: BoxImageURLs

    /// The row the list already had, so the screen can open with a title
    /// instead of a spinner and a blank bar.
    private let placeholderTitle: String

    private var box: Box?
    private var photoURL: URL?
    private var failure: InventoryFailure?
    /// Items with a write in flight, so a second tap cannot race the first.
    private var busyItemIDs: Set<String> = []

    init(
        boxID: String,
        title: String,
        userID: String,
        reader: any InventoryReading = InventoryRepository(),
        writer: any InventoryWriting = InventoryWriteRepository(),
        imageURLs: BoxImageURLs = BoxImageURLs()
    ) {
        self.boxID = boxID
        self.placeholderTitle = title
        self.userID = userID
        self.reader = reader
        self.writer = writer
        self.imageURLs = imageURLs
    }

    var viewState: BoxDetailViewState {
        BoxDetailViewState(
            title: box.map { InventoryCopy.boxName($0.name) } ?? placeholderTitle,
            isEditVisible: box != nil,
            content: content
        )
    }

    private var content: BoxDetailViewState.Content {
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        guard let box else { return .loading }

        return .loaded(
            BoxDetailViewState.Loaded(
                symbol: BoxSymbols.symbol(forIconKey: box.icon),
                location: box.location?.trimmed.nilIfEmpty,
                imageURL: photoURL,
                itemCount: InventoryCopy.itemCount(box.items.count),
                takenNote: InventoryCopy.takenNote(box.items.filter(\.isTaken).count),
                items: box.items.map {
                    BoxDetailViewState.ItemRow(
                        id: $0.id,
                        name: InventoryCopy.itemName($0.name),
                        quantity: $0.quantity > 1 ? "×\($0.quantity)" : nil,
                        isTaken: $0.isTaken,
                        isBusy: busyItemIDs.contains($0.id)
                    )
                },
                emptyMessage: box.items.isEmpty ? InventoryCopy.emptyBox : nil
            )
        )
    }

    // MARK: - Intents

    func appeared() async {
        guard box == nil else { return }
        await load()
    }

    /// Reloads after the editor has been and gone.
    func returnedToScreen() async {
        await load()
    }

    func retryTapped() async {
        await load()
    }

    /// Taking or returning one item. Written straight through rather than
    /// batched into a save: this is a one-tap action on a screen with no save
    /// button, and the row it touches is the row being looked at.
    func itemTapped(_ itemID: String) async {
        guard let box, let item = box.items.first(where: { $0.id == itemID }) else { return }
        guard !busyItemIDs.contains(itemID) else { return }

        busyItemIDs.insert(itemID)
        defer { busyItemIDs.remove(itemID) }

        do {
            try await writer.setItemTaken(itemID: itemID, isTaken: !item.isTaken, userID: userID)
            await load()
        } catch {
            failure = InventoryFailure.from(error)
        }
    }

    private func load() async {
        failure = nil
        do {
            let box = try await reader.box(id: boxID)
            self.box = box
            photoURL = await imageURLs.resolve(box.imageURL)
        } catch {
            failure = InventoryFailure.from(error)
        }
    }
}
