import Foundation

/// A link the app knows how to open.
enum DeepLink: Equatable, Sendable {
    case invite(code: String, householdName: String?)
    case openBox(id: String)
}

/// Parses and builds the two link shapes every client shares:
///
///     https://boxandfound.net/?invite=CODE&name=Household
///     https://boxandfound.net/?box=ID
///
/// Works on a plain string rather than `URL` so it can be tested without one,
/// and because the query-parameter names are a contract with the web client —
/// a contract that cannot be tested drifts. Ported from the Android client's
/// `InviteLink`, including the precedence rule.
enum InviteLink {

    /// Matches the web client's `buildInviteUrl`.
    static func inviteURL(code: String, householdName: String?, siteURL: String) -> String {
        let base = trimTrailingSlashes(siteURL)
        var url = "\(base)/?invite=\(encode(code))"
        if let name = householdName?.trimmed, !name.isEmpty {
            url += "&name=\(encode(name))"
        }
        return url
    }

    static func boxURL(id: String, siteURL: String) -> String {
        "\(trimTrailingSlashes(siteURL))/?box=\(encode(id))"
    }

    /// Nil when the URL is not one of ours, or carries neither parameter.
    static func parse(_ url: String?) -> DeepLink? {
        guard let url, !url.trimmed.isEmpty else { return nil }

        // Take the query off by hand rather than via URLComponents: a custom
        // scheme with an odd shape still has to yield its parameters, and the
        // fragment is never ours.
        guard let queryStart = url.firstIndex(of: "?") else { return nil }
        var query = String(url[url.index(after: queryStart)...])
        if let fragment = query.firstIndex(of: "#") {
            query = String(query[..<fragment])
        }
        guard !query.isEmpty else { return nil }

        var params: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            let value = parts.count > 1 ? decode(String(parts[1])) : ""
            // First wins: a repeated parameter is malformed, and taking the
            // later one would let an appended `&invite=` override the first.
            if params[key] == nil { params[key] = value }
        }

        // An invite wins over a box: a link carrying both is asking you to join
        // first, and joining is what makes the box readable at all.
        if let code = params["invite"]?.trimmed, !code.isEmpty {
            let name = params["name"]?.trimmed
            return .invite(code: code, householdName: name?.isEmpty == true ? nil : name)
        }
        if let box = params["box"]?.trimmed, !box.isEmpty {
            return .openBox(id: box)
        }
        return nil
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var trimmed = value.trimmed
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// A malformed escape should cost the parameter its decoding, not the whole
    /// link — the same forgiveness the Android parser shows.
    private static func decode(_ value: String) -> String {
        let plussesAsSpaces = value.replacingOccurrences(of: "+", with: " ")
        return plussesAsSpaces.removingPercentEncoding ?? plussesAsSpaces
    }
}

/// Invite codes, in the shape every client reads and types.
enum InviteCode {

    /// Matches the web client's `randomCode()`: six characters of upper-case
    /// base 36. Codes get read aloud and typed in, so the shape has to stay
    /// identical across clients.
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let length = 6

    static func random(using generator: () -> Int = { Int.random(in: 0..<alphabet.count) }) -> String {
        String((0..<length).map { _ in alphabet[generator() % alphabet.count] })
    }

    /// What someone typed, in the form the server stores. Codes are read off a
    /// screen and typed back in, so case and stray spaces are the person's
    /// problem to make and this one to forgive.
    static func normalise(_ raw: String) -> String {
        raw.trimmed.uppercased().filter { alphabet.contains($0) }
    }

    static func isPlausible(_ raw: String) -> Bool {
        normalise(raw).count == length
    }
}
