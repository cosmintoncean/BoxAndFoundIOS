import Foundation

/// What a kind of container looks like and is called.
///
/// Shared by the storage screen and the box list, so a wardrobe is the same
/// wardrobe wherever it turns up. The type itself is free text to the database
/// — the catalogue lives in the clients — so a kind a newer build invented
/// still reads as a container here rather than as nothing.
///
/// SF Symbols standing in for the web's own glyphs, on the same terms as
/// `BoxSymbols`: the nearest system symbol to each, total by construction.
enum ContainerLook {

    static func symbol(for type: String) -> String {
        switch type {
        case "wardrobe": "hanger"
        case "shelving", "shelf": "books.vertical"
        case "cabinet": "cabinet"
        case "drawer": "tray"
        case "cupboard": "door.left.hand.closed"
        case "chest": "archivebox"
        case "rack": "square.grid.3x2"
        case "closet": "door.right.hand.closed"
        case "crate": "shippingbox"
        default: "tray.2"
        }
    }

    /// Title case, because these name a thing rather than describe one.
    static func label(for type: String) -> String {
        switch type {
        case "wardrobe": "Wardrobe"
        case "shelving": "Shelving"
        case "shelf": "Shelf"
        case "cabinet": "Cabinet"
        case "drawer": "Drawer"
        case "cupboard": "Cupboard"
        case "chest": "Chest"
        case "rack": "Rack"
        case "closet": "Closet"
        case "crate": "Crate"
        case "other": "Other"
        // A type this build has never heard of is still a container; calling
        // it by its own name beats calling it "Other".
        default: type.capitalisedFirst
        }
    }
}

private extension String {
    var capitalisedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
