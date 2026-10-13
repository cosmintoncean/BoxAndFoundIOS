import Foundation

/// Where storage becomes words.
enum StorageCopy {

    static let emptyRoom = "Nothing is stored in this room yet."
    static let emptyContainer = "This is empty."

    static func tooDeep(limit: Int) -> String {
        "Storage can nest \(limit) levels deep, and this is the last one."
    }

    /// What a container holds, the way someone opening it would say it.
    ///
    /// Only the parts that are actually there: a wardrobe with two boxes and
    /// nothing else says "2 boxes", not "2 boxes · 0 containers · 0 loose".
    static func contents(_ contents: PlaceContents) -> String {
        var parts: [String] = []
        if contents.boxes > 0 {
            parts.append(contents.boxes == 1 ? "1 box" : "\(contents.boxes) boxes")
        }
        if contents.containers > 0 {
            parts.append(
                contents.containers == 1 ? "1 container" : "\(contents.containers) containers"
            )
        }
        if contents.looseItems > 0 {
            parts.append("\(contents.looseItems) loose")
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    /// "×2", and nothing at all for a single one — a quantity on every row
    /// would be noise where almost everything is one.
    static func quantity(_ count: Int) -> String? {
        count > 1 ? "×\(count)" : nil
    }
}
