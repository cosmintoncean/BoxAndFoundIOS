import Foundation

/// Everything the box list draws. No `Box`, no `BoxMatch`, no `Room`: counts
/// are already sentences, icons are already symbol names, and the reason a box
/// is in the results has already been worded.
struct InventoryViewState: Equatable {

    struct HouseholdOption: Equatable, Identifiable {
        let id: String
        let name: String
    }

    /// Hashable because it is the navigation value for the detail screen —
    /// the row itself is what gets pushed, so the destination opens with a
    /// title and an icon already in hand.
    struct BoxRow: Hashable, Identifiable {
        let id: String
        let name: String
        /// An SF Symbol name. The `boxes.icon` key is a cross-client contract;
        /// which picture it becomes is this layer's business alone.
        let symbol: String
        let location: String?
        /// "4 items", "1 item", "Empty" — decided here so no view counts.
        let itemCount: String
        /// "2 taken", or nil when nothing is out.
        let takenNote: String?
        /// Why this box survived the search, when that is not obvious from its
        /// name — "Matches: Gloves, Scarf". Nil when not searching.
        let matchNote: String?
    }

    struct RoomSection: Equatable, Identifiable {
        let id: String
        let title: String
        /// Nil for the unassigned group: it is not a room, so it has no map.
        let roomID: String?
        let boxes: [BoxRow]
    }

    /// One tag in the bar above the list.
    struct TagChip: Equatable, Identifiable {
        let id: String
        let label: String
        /// How much of this tag is about — per use, as the web counts it, so a
        /// tag on a box and on two of its items reads 3.
        let count: Int
        let isActive: Bool
        /// Read off the items rather than typed by anyone, and shown apart
        /// from the rest.
        let isDerived: Bool
    }

    enum Content: Equatable {
        case loading
        /// Nothing to show, and why — no households, no boxes, or no results.
        case empty(message: String)
        case failed(message: String)
        case sections([RoomSection])
    }

    var title: String
    var households: [HouseholdOption]
    var activeHouseholdID: String?
    /// One household needs no switcher.
    var isHouseholdSwitcherVisible: Bool
    var searchTerm: String
    var isSearchVisible: Bool
    /// Every tag in use, in a bar above the list. Empty when nothing is
    /// tagged, which is most households for a while.
    var tags: [TagChip] = []
    var content: Content
}
