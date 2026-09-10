import Foundation

/// The twelve `boxes.icon` keys.
///
/// A contract between the clients, not a local enum: a box saved with a key
/// another side does not recognise renders as that side's fallback. The order
/// is the web client's own, from the icon picker in `index.html`, and
/// `defaultKey` matches its `DEFAULT_ICON`.
///
/// How a key becomes a picture is a presentation problem and lives there.
enum BoxIcons {
    static let defaultKey = "box"

    static let keys: [String] = [
        "box", "casserole", "bag", "backpack", "suitcase", "cardbox",
        "basket", "bucket", "cabinet", "folder", "gift", "toy",
    ]

    /// Falls back to the default for an unknown or missing key, as the web does.
    static func normalise(_ key: String?) -> String {
        guard let key, keys.contains(key) else { return defaultKey }
        return key
    }
}
