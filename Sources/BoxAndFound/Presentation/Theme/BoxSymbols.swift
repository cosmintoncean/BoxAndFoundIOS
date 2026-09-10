import Foundation

/// Turns a `boxes.icon` key into a picture.
///
/// **Interim.** Android generates real vector drawables from the web client's
/// own SVGs (`tools/svg2vector.js`), so a box looks identical on both. These
/// are SF Symbols standing in for that — the nearest system glyph to each of
/// the twelve. They read correctly and ship today; they are not pixel parity,
/// and converting the SVGs into an asset catalogue is the job that replaces
/// this file.
///
/// The mapping is total by construction: an unknown key is normalised to the
/// default first, so this can never fail to return something.
enum BoxSymbols {
    static func symbol(forIconKey key: String?) -> String {
        switch BoxIcons.normalise(key) {
        case "casserole": "fork.knife"
        case "bag": "bag"
        case "backpack": "backpack"
        case "suitcase": "suitcase"
        case "cardbox": "archivebox"
        case "basket": "basket"
        case "bucket": "bucket"
        case "cabinet": "cabinet"
        case "folder": "folder"
        case "gift": "gift"
        case "toy": "teddybear"
        default: "shippingbox"
        }
    }
}
