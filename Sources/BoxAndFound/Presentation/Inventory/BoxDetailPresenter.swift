import Foundation
import Observation

/// Drives one box: what is in it, and what is out.
@MainActor
@Observable
final class BoxDetailPresenter: Presenter {

    private let boxID: String
    private let repository: any InventoryReading

    /// The row the list already had, so the screen can open with a title and
    /// an icon instead of a spinner and a blank bar.
    private let placeholderTitle: String

    private var box: Box?
    private var failure: InventoryFailure?

    init(
        boxID: String,
        title: String,
        repository: any InventoryReading = InventoryRepository()
    ) {
        self.boxID = boxID
        self.placeholderTitle = title
        self.repository = repository
    }

    var viewState: BoxDetailViewState {
        BoxDetailViewState(
            title: box.map { InventoryCopy.boxName($0.name) } ?? placeholderTitle,
            content: content
        )
    }

    private var content: BoxDetailViewState.Content {
        if let failure { return .failed(message: InventoryCopy.message(for: failure)) }
        guard let box else { return .loading }

        return .loaded(
            BoxDetailViewState.Loaded(
                symbol: BoxSymbols.symbol(forIconKey: box.icon),
                location: box.location?.isEmpty == false ? box.location : nil,
                imageURL: box.imageURL.flatMap(URL.init(string:)),
                itemCount: InventoryCopy.itemCount(box.items.count),
                takenNote: InventoryCopy.takenNote(box.items.filter(\.isTaken).count),
                items: box.items.map {
                    BoxDetailViewState.ItemRow(
                        id: $0.id,
                        name: InventoryCopy.itemName($0.name),
                        // A quantity of one on every row is noise.
                        quantity: $0.quantity > 1 ? "×\($0.quantity)" : nil,
                        isTaken: $0.isTaken
                    )
                },
                emptyMessage: box.items.isEmpty ? InventoryCopy.emptyBox : nil
            )
        )
    }

    func appeared() async {
        guard box == nil else { return }
        await load()
    }

    func retryTapped() async {
        await load()
    }

    private func load() async {
        // No separate loading flag: no box and no failure is what loading is.
        failure = nil
        do {
            box = try await repository.box(id: boxID)
        } catch {
            failure = InventoryFailure.from(error)
        }
    }
}
