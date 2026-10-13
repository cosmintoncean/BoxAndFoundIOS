import Foundation

/// One level of storage: what is directly inside a room, or directly inside a
/// container.
///
/// Deliberately one level rather than a tree on screen. The data is a tree and
/// `Places` treats it as one, but a person opening a wardrobe is looking at
/// its shelf, not at an outline of the whole house — and a nested disclosure
/// list on a phone is a lot of chevrons to read before finding anything.
struct StorageViewState: Equatable {

    /// A container or a box: something you can open.
    struct PlaceRow: Equatable, Identifiable {
        let id: String
        let name: String
        let symbol: String
        /// "Wardrobe" for a container, nil for a box — a box says what it
        /// holds instead, and "Box" on every row is noise.
        let kindLabel: String?
        /// "2 boxes · 3 loose", or "4 items" for a box.
        let detail: String
        let isContainer: Bool
    }

    /// Something sitting in this container itself rather than in a box inside
    /// it.
    struct LooseItemRow: Equatable, Identifiable {
        let id: String
        let name: String
        /// "×2", and nil for a single one.
        let quantity: String?
        let isTaken: Bool
        let tags: [String]
    }

    struct Contents: Equatable {
        /// Room first: Attic › Wardrobe › Drawer 2. Empty at a room's own
        /// level, where the title already says where you are.
        let path: [String]
        let containers: [PlaceRow]
        let boxes: [PlaceRow]
        let looseItems: [LooseItemRow]
        /// Said once, when there is nothing here at all.
        let emptyMessage: String?
        /// Why nothing more can go inside this one.
        let depthNote: String?
    }

    enum Content: Equatable {
        case loading
        case failed(message: String)
        case contents(Contents)
    }

    var title: String
    var content: Content
}
