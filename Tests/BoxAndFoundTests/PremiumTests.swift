import Foundation
import Testing
@testable import BoxAndFound

@Suite("Premium entitlement")
struct PremiumTests {

    private let now = Date(timeIntervalSince1970: 1_757_000_000) // 2025-09-04T15:33:20Z
    private let future = "2030-01-01T00:00:00Z"
    private let past = "2020-01-01T00:00:00Z"

    @Test("The allowlist wins outright, whatever the metadata says")
    func allowlist() {
        #expect(Premium.isPremium(
            email: "Owner@Example.com", isPremiumFlag: false, plan: nil, until: past,
            allowlist: ["owner@example.com"], now: now
        ))
    }

    @Test("An unparsed template allowlist grants nobody anything")
    func templateAllowlist() {
        #expect(Premium.parseEmailList("{{PREMIUM_EMAILS}}").isEmpty)
        #expect(Premium.parseEmailList(nil).isEmpty)
        #expect(Premium.parseEmailList("  ").isEmpty)
        #expect(Premium.parseEmailList("A@b.com, c@d.com ,") == ["a@b.com", "c@d.com"])
    }

    @Test("is_premium false is the end of it")
    func flagOff() {
        #expect(!Premium.isPremium(
            email: "someone@example.com", isPremiumFlag: false, plan: "lifetime", until: future,
            allowlist: [], now: now
        ))
        #expect(!Premium.isPremium(
            email: "someone@example.com", isPremiumFlag: nil, plan: nil, until: nil,
            allowlist: [], now: now
        ))
    }

    @Test("Lifetime never expires")
    func lifetime() {
        #expect(Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: "lifetime", until: past,
            allowlist: [], now: now
        ))
    }

    @Test("A dated plan is premium until its date")
    func expiry() {
        #expect(Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: "yearly", until: future,
            allowlist: [], now: now
        ))
        #expect(!Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: "yearly", until: past,
            allowlist: [], now: now
        ))
    }

    @Test("An unparseable expiry is not premium — the safe way to fail")
    func unparseableExpiry() {
        #expect(!Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: "yearly", until: "not a date",
            allowlist: [], now: now
        ))
    }

    @Test("is_premium with nothing else is premium, matching the web client")
    func flagWithoutEnrichment() {
        #expect(Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: nil, until: nil,
            allowlist: [], now: now
        ))
        #expect(Premium.isPremium(
            email: nil, isPremiumFlag: true, plan: nil, until: "   ",
            allowlist: [], now: now
        ))
    }

    @Test("Both timestamp shapes Postgres and PostgREST produce parse to the same instant")
    func timestampShapes() {
        let iso = Premium.parseTimestamp("2026-01-01T00:00:00+00:00")
        let spaced = Premium.parseTimestamp("2026-01-01 00:00:00+00")
        let fractional = Premium.parseTimestamp("2026-01-01T00:00:00.123456+00:00")
        #expect(iso != nil)
        #expect(iso == spaced)
        #expect(fractional != nil)
        // Tolerant: the formatter may truncate to milliseconds, which is fine —
        // what matters is that the fractional form is not silently rejected.
        if let iso, let fractional {
            #expect(abs(fractional.timeIntervalSince(iso) - 0.123456) < 0.001)
        }
    }

    @Test("A non-timestamp is nil rather than a wrong instant")
    func timestampRejects() {
        #expect(Premium.parseTimestamp("") == nil)
        #expect(Premium.parseTimestamp("2026-01-01") == nil)
        #expect(Premium.parseTimestamp("tomorrow") == nil)
    }
}
