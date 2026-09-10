import Foundation

/// Where the inventory becomes words. The counterpart of `AuthCopy`, and for
/// the same reason: no repository carries a sentence, and no view sees a
/// `InventoryFailure`.
enum InventoryCopy {

    static let unassignedRoom = "No room"
    static let noHouseholds = "You are not in a household yet. Create one on the web to get started."
    static let noBoxes = "No boxes in this household yet."
    static let emptyBox = "Nothing in this box yet."

    static func noResults(for term: String) -> String {
        "Nothing matches \u{201C}\(term)\u{201D}."
    }

    static func message(for failure: InventoryFailure) -> String {
        switch failure {
        case .network:
            "No connection. Check your network and try again."
        case .notFound:
            "That box is no longer here."
        case .unknown:
            "Something went wrong. Try again."
        }
    }

    /// "4 items", "1 item", "Empty". Pluralised here so no view has to.
    static func itemCount(_ count: Int) -> String {
        switch count {
        case 0: "Empty"
        case 1: "1 item"
        default: "\(count) items"
        }
    }

    /// Nil when nothing is out — an absent line reads better than "0 taken".
    static func takenNote(_ count: Int) -> String? {
        count == 0 ? nil : "\(count) taken"
    }

    /// Why a box is in the results, when its own name does not say so.
    ///
    /// Only the first few are named: a box with thirty matching items would
    /// otherwise push every other result off the screen.
    static func matchNote(itemNames: [String], limit: Int = 3) -> String? {
        let named = itemNames.filter { !$0.isEmpty }
        guard !named.isEmpty else { return nil }
        let shown = named.prefix(limit).joined(separator: ", ")
        let remainder = named.count - min(limit, named.count)
        return remainder > 0 ? "Matches: \(shown) +\(remainder) more" : "Matches: \(shown)"
    }

    /// A box with no name still needs something to tap.
    static func boxName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Untitled box"
        }
        return name
    }

    /// An item with no name still needs a row.
    static func itemName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Untitled item"
        }
        return name
    }

    static func householdName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Household"
        }
        return name
    }

    static func roomName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return unassignedRoom
        }
        return name
    }
}
