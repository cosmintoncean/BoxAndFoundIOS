import Testing
@testable import BoxAndFound

@Suite("Invite and box links")
struct DeepLinkTests {

    private let site = "https://boxandfound.net"

    // MARK: - Parsing

    @Test("An invite link yields its code and the household name")
    func parsesInvite() {
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123&name=Home")
                == .invite(code: "ABC123", householdName: "Home")
        )
    }

    @Test("A household name is percent-decoded, spaces and all")
    func decodesName() {
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123&name=The%20Flat")
                == .invite(code: "ABC123", householdName: "The Flat")
        )
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123&name=The+Flat")
                == .invite(code: "ABC123", householdName: "The Flat")
        )
    }

    @Test("An invite with no name is still an invite")
    func inviteWithoutName() {
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123")
                == .invite(code: "ABC123", householdName: nil)
        )
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123&name=")
                == .invite(code: "ABC123", householdName: nil)
        )
    }

    @Test("A box link yields its id")
    func parsesBox() {
        #expect(InviteLink.parse("https://boxandfound.net/?box=abc-123") == .openBox(id: "abc-123"))
    }

    /// A link carrying both is asking you to join first — joining is what
    /// makes the box readable at all.
    @Test("An invite wins over a box on a link carrying both")
    func inviteBeatsBox() {
        #expect(
            InviteLink.parse("https://boxandfound.net/?box=abc&invite=XYZ789")
                == .invite(code: "XYZ789", householdName: nil)
        )
    }

    @Test("A fragment is not part of the query")
    func ignoresFragment() {
        #expect(
            InviteLink.parse("https://boxandfound.net/?invite=ABC123#section")
                == .invite(code: "ABC123", householdName: nil)
        )
    }

    @Test("The custom scheme parses the same way as the web one")
    func customSchemeParses() {
        #expect(
            InviteLink.parse("net.boxandfound.ios://open?invite=ABC123")
                == .invite(code: "ABC123", householdName: nil)
        )
    }

    @Test("Anything without our parameters is not our link", arguments: [
        "", "   ", "https://boxandfound.net/", "https://boxandfound.net/?",
        "https://example.com/?utm_source=x", "not a url at all",
        "https://boxandfound.net/?invite=", "https://boxandfound.net/?box=",
    ])
    func rejectsEverythingElse(_ url: String) {
        #expect(InviteLink.parse(url) == nil)
    }

    @Test("A nil URL is not a link")
    func rejectsNil() {
        #expect(InviteLink.parse(nil) == nil)
    }

    /// A broken escape should cost that parameter its decoding, not lose the
    /// whole link.
    @Test("A malformed escape does not throw the link away")
    func survivesBadEscapes() {
        #expect(InviteLink.parse("https://boxandfound.net/?invite=ABC%ZZ") != nil)
    }

    // MARK: - Building

    @Test("An invite URL round-trips back into the same invite")
    func inviteRoundTrips() {
        let url = InviteLink.inviteURL(code: "ABC123", householdName: "The Flat", siteURL: site)
        #expect(InviteLink.parse(url) == .invite(code: "ABC123", householdName: "The Flat"))
    }

    @Test("A box URL round-trips")
    func boxRoundTrips() {
        let url = InviteLink.boxURL(id: "box-42", siteURL: site)
        #expect(InviteLink.parse(url) == .openBox(id: "box-42"))
    }

    @Test("A trailing slash on the site URL does not double up")
    func trimsTrailingSlash() {
        #expect(
            InviteLink.inviteURL(code: "ABC", householdName: nil, siteURL: "https://boxandfound.net/")
                == "https://boxandfound.net/?invite=ABC"
        )
    }

    @Test("A blank household name is left off rather than sent empty")
    func blankNameIsOmitted() {
        #expect(
            InviteLink.inviteURL(code: "ABC", householdName: "   ", siteURL: site)
                == "https://boxandfound.net/?invite=ABC"
        )
    }
}

@Suite("Invite codes")
struct InviteCodeTests {

    @Test("A generated code matches the shape every client reads")
    func shape() {
        for _ in 0..<50 {
            let code = InviteCode.random()
            #expect(code.count == InviteCode.length)
            #expect(code.allSatisfy { InviteCode.alphabet.contains($0) })
        }
    }

    /// Codes are read off a screen and typed back in, so case and stray
    /// spaces are the person's to get wrong and this one's to forgive.
    @Test("Typed codes are forgiven their case and spacing")
    func normalising() {
        #expect(InviteCode.normalise("  abc123 ") == "ABC123")
        #expect(InviteCode.normalise("abc-123") == "ABC123")
        #expect(InviteCode.normalise("a b c 1 2 3") == "ABC123")
    }

    @Test("Only a full-length code is worth a round trip")
    func plausibility() {
        #expect(InviteCode.isPlausible("abc123"))
        #expect(InviteCode.isPlausible(" ABC123 "))
        #expect(!InviteCode.isPlausible("ABC12"))
        #expect(!InviteCode.isPlausible("ABC1234"))
        #expect(!InviteCode.isPlausible(""))
    }
}
