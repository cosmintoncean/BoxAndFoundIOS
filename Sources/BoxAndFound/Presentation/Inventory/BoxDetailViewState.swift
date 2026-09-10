import Foundation

/// Everything the box detail screen draws.
struct BoxDetailViewState: Equatable {

    struct ItemRow: Equatable, Identifiable {
        let id: String
        let name: String
        /// "×3", or nil for a single one — "×1" on every row is noise.
        let quantity: String?
        let isTaken: Bool
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
    var content: Content
}
