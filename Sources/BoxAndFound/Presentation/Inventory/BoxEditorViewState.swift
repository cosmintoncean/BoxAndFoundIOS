import Foundation

/// Everything the box editor draws.
struct BoxEditorViewState: Equatable {

    struct ItemRow: Equatable, Identifiable {
        /// Local to the editor and stable for as long as the row is on screen.
        /// A new item has no database id until it is saved, and SwiftUI still
        /// needs something to identify it by.
        let id: String
        let name: String
        let quantity: Int
        /// "×3", or nil for a single one.
        let quantityLabel: String?
        let isTaken: Bool
    }

    struct IconOption: Equatable, Identifiable {
        let key: String
        let symbol: String
        let isSelected: Bool
        var id: String { key }
    }

    struct RoomOption: Equatable, Identifiable {
        /// Empty for "No room" — `boxes.room_id` is nullable.
        let id: String
        let name: String
        let isSelected: Bool
    }

    struct Notice: Equatable {
        enum Kind: Equatable { case error, success }
        let kind: Kind
        let text: String
    }

    enum Photo: Equatable {
        case none
        /// Already on the box. Nil URL means it could not be signed.
        case existing(URL?)
        /// Chosen in this session and not uploaded yet.
        case picked
    }

    var title: String
    var isLoading: Bool

    var name: String
    var location: String
    var icons: [IconOption]
    var rooms: [RoomOption]
    var items: [ItemRow]
    var newItemName: String
    var photo: Photo

    var saveTitle: String
    var isSaveEnabled: Bool
    var isSaving: Bool
    var isDeleteVisible: Bool
    var notice: Notice?

    /// Flips once the write has landed, so the view can pop. The presenter
    /// decides when the screen is done, not the button that started it.
    var isFinished: Bool
}
