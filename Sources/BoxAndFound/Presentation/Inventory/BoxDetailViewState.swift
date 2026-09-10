import Foundation

/// Everything the box detail screen draws.
struct BoxDetailViewState: Equatable {

    struct ItemRow: Equatable, Identifiable {
        let id: String
        let name: String
        /// "×3", or nil for a single one — "×1" on every row is noise.
        let quantity: String?
        let isTaken: Bool
        /// A write is in flight for this row, so a second tap is refused and
        /// the row can say why it looks unresponsive.
        let isBusy: Bool
    }

    struct Loaded: Equatable {
        let symbol: String
        let location: String?
        let imageURL: URL?
        let itemCount: String
        let takenNote: String?
        let items: [ItemRow]
        /// Shown in place of the list when the box has nothing in it.
        let emptyMessage: String?
    }

    enum Content: Equatable {
        case loading
        case failed(message: String)
        case loaded(Loaded)
    }

    var title: String
    /// Nothing to edit until the box has actually arrived.
    var isEditVisible: Bool
    var content: Content
}
