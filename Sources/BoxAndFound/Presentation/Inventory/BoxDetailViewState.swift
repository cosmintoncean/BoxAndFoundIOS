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
        /// Offered only for an item someone else took. Asking yourself for
        /// something back is not a feature.
        let canAskBack: Bool
    }

    /// The sheet for asking an item back.
    struct NudgeSheet: Equatable {
        let itemID: String
        let title: String
        let message: String
        /// "You asked recently. You can ask again in about 3 hours." Nil when
        /// the window is clear.
        let cooldownNote: String?
        let canSend: Bool
        let isSending: Bool
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
        /// Requests pointed at this person for items in this box, already
        /// worded — "Cosmin asked for the Scarf back".
        let pendingNotes: [String]
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
    var nudgeSheet: NudgeSheet?
    /// Said once, after a request goes out.
    var notice: String?
}
