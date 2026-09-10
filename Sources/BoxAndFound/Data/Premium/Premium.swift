import Foundation

/// Entitlement, ported from the web client's `checkPremium` by way of the
/// Android client's `Premium`.
///
/// Premium is three fields on `user_metadata` — `is_premium`, `premium_plan`,
/// `premium_until` — plus a build-time allowlist for the owner and testers.
/// Keeping the shape identical is what lets StoreKit (M6), Play Billing and the
/// existing Lemon Squeezy webhook write the same thing and have all three
/// clients read it the same way: many writers, one shape.
///
/// Pure, so it can be tested without a Supabase session.
enum Premium {

    /// Parses the comma-separated allowlist, ignoring an unsubstituted template.
    static func parseEmailList(_ raw: String?) -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              !raw.hasPrefix("{{") else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func isPremium(
        email: String?,
        isPremiumFlag: Bool?,
        plan: String?,
        until: String?,
        allowlist: [String],
        now: Date,
        parseInstant: (String) -> Date? = Premium.parseTimestamp
    ) -> Bool {
        let normalised = email?.lowercased() ?? ""
        if !normalised.isEmpty && allowlist.contains(normalised) { return true }

        guard isPremiumFlag == true else { return false }

        // Lifetime never expires.
        if plan == "lifetime" { return true }

        if let until, !until.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let expiry = parseInstant(until) else { return false }
            return expiry > now
        }

        // is_premium true with no plan or expiry yet: the web client treats this
        // as premium, on the grounds that the webhook may not have enriched the
        // record. Diverging here would lock out someone who has just paid.
        return true
    }

    /// Accepts both what PostgREST returns for a `timestamptz`
    /// (`2026-09-08T10:00:00+00:00`, sometimes with fractional seconds) and the
    /// space-separated `2026-09-08 10:00:00+00` form Postgres prints, which
    /// `ISO8601DateFormatter` rejects on both counts.
    static func parseTimestamp(_ value: String) -> Date? {
        var text = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")

        // A two-digit trailing offset ("+00") needs its minutes to parse. Only
        // applied once a time component is present, so a bare date is left to
        // fail rather than being turned into nonsense.
        if text.contains("T"), let sign = text.lastIndex(where: { $0 == "+" || $0 == "-" }),
           text.distance(from: sign, to: text.endIndex) == 3 {
            text += ":00"
        }

        for options in [
            ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
            ISO8601DateFormatter.Options([.withInternetDateTime]),
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
