import Foundation

/// What a stored `boxes.image_url` actually is.
///
/// The `box-images` bucket used to be public, so the column held an absolute
/// URL. It is private now: a photo is reachable only through a URL signed for
/// the current session, and that URL expires — so the value on the row can no
/// longer be the value handed to an image loader.
///
/// Three shapes reach it, and each is left as it is rather than normalised
/// into the others:
///
/// - `data:…` — a photo the web client kept inline in local mode. Loadable.
/// - `https://…` — written before the bucket was closed, or pointing
///   somewhere else entirely. Passed through; a failure falls back to the box
///   glyph, which is what a box with no photo shows anyway.
/// - `abc/1.png` — a storage path, and the only shape that needs signing.
///
/// Free-standing and pure so the rule can be tested on its own: getting it
/// wrong means either signing a `data:` URL or handing a loader a bare path,
/// and both fail silently.
enum BoxImagePath {
    static func needsSigning(_ value: String) -> Bool {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return false }
        let schemes = ["data:", "http://", "https://"]
        return !schemes.contains { trimmed.lowercased().hasPrefix($0) }
    }
}
