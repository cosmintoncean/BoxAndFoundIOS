import Foundation

/// A patch for a box: only the fields the editor changed.
///
/// Sending the whole row instead would overwrite whatever another member
/// edited in the meantime — the same class of bug the item diff exists to
/// avoid, one table up.
struct BoxChanges: Equatable, Sendable {
    var name: FieldChange<String> = .unchanged
    var icon: FieldChange<String> = .unchanged
    var location: FieldChange<String> = .unchanged
    var roomID: FieldChange<String> = .unchanged
    var imageURL: FieldChange<String> = .unchanged

    var isEmpty: Bool {
        name == .unchanged
            && icon == .unchanged
            && location == .unchanged
            && roomID == .unchanged
            && imageURL == .unchanged
    }
}
