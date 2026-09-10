import Foundation

/// Small enough to be tempting to redefine per file, common enough that three
/// copies would drift. Kept in the domain because that is the innermost layer
/// that uses them.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
