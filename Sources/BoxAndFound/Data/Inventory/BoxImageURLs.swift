import Foundation
import Supabase

/// Turns whatever `boxes.image_url` holds into something an image loader can
/// actually fetch. See `BoxImagePath` for the three shapes that arrive.
///
/// An actor rather than a lock: the cache is read from presenters on the main
/// actor and written from whichever task signed the URL, and this is the
/// smallest thing that makes that safe.
///
/// Signed URLs are cached until shortly before they expire. Two callers racing
/// for the same cold path will both sign it — harmless, and cheaper than the
/// bookkeeping to prevent it, since it can only happen once per path per hour.
actor BoxImageURLs {

    private struct Signed {
        let url: URL
        let usableUntil: Date
    }

    private let client: SupabaseClient
    private var cache: [String: Signed] = [:]

    init(client: SupabaseClient = SupabaseProvider.shared) {
        self.client = client
    }

    /// A loadable URL, or nil when the value is absent or could not be
    /// signed — a photo deleted from the bucket, or one belonging to a
    /// household this user has since left. Callers show the box glyph for nil,
    /// which is what they already show for a box with no photo at all.
    func resolve(_ value: String?) async -> URL? {
        let raw = (value ?? "").trimmed
        guard !raw.isEmpty else { return nil }
        guard BoxImagePath.needsSigning(raw) else { return URL(string: raw) }

        if let cached = cache[raw], cached.usableUntil > Date() {
            return cached.url
        }

        do {
            let url = try await client.storage
                .from(AppConfig.storageBucket)
                .createSignedURL(path: raw, expiresIn: Self.ttlSeconds)
            cache[raw] = Signed(url: url, usableUntil: Date().addingTimeInterval(Self.usableForSeconds))
            return url
        } catch {
            return nil
        }
    }

    /// Drops a cached URL so the next `resolve` signs afresh.
    func forget(_ path: String) {
        cache.removeValue(forKey: path)
    }

    /// Forgets this session's photos. Called on sign-out for the same reason
    /// the remembered household is cleared there: one account's photos should
    /// not stay readable for whoever signs in next.
    func clear() {
        cache.removeAll()
    }

    private static let ttlSeconds = 60 * 60

    /// Deliberately shorter than the TTL: an image already on screen when the
    /// clock runs out should be re-signed on its next load rather than
    /// failing, so a cached URL is treated as dead a little early.
    private static let usableForSeconds: TimeInterval = 55 * 60
}
