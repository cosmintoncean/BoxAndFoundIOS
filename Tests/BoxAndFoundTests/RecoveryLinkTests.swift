import Foundation
import Testing
@testable import BoxAndFound

/// The marker in the callback is the only thing separating a password-reset
/// arrival from an ordinary OAuth sign-in — both come back on the same scheme
/// and both establish a session.
@Suite("Recovery link")
struct RecoveryLinkTests {

    @Test("A recovery callback is recognised wherever the marker sits")
    func recognisesRecovery() throws {
        let fragments = [
            "net.boxandfound.ios://login-callback#access_token=abc&expires_in=3600&type=recovery",
            "net.boxandfound.ios://login-callback#type=recovery&access_token=abc",
            "net.boxandfound.ios://login-callback#type=recovery",
        ]
        for raw in fragments {
            let url = try #require(URL(string: raw))
            #expect(RecoveryLink.isRecovery(url))
        }
    }

    @Test("The PKCE flow puts the marker in the query instead")
    func recognisesQueryForm() throws {
        let url = try #require(URL(string: "net.boxandfound.ios://login-callback?type=recovery&code=abc"))
        #expect(RecoveryLink.isRecovery(url))
    }

    @Test("An OAuth callback is not a recovery")
    func ignoresOAuth() throws {
        let others = [
            "net.boxandfound.ios://login-callback#access_token=abc&token_type=bearer",
            "net.boxandfound.ios://login-callback#type=signup",
            "net.boxandfound.ios://login-callback",
            "https://boxandfound.net/?invite=ABC123",
        ]
        for raw in others {
            let url = try #require(URL(string: raw))
            #expect(!RecoveryLink.isRecovery(url))
        }
    }

    @Test("A parameter merely ending in type is not the type parameter")
    func ignoresLookalikeParameter() throws {
        // `token_type=recovery` is not something GoTrue sends, but matching a
        // whole parameter is what keeps a lookalike off the reset screen.
        let url = try #require(URL(string: "net.boxandfound.ios://login-callback#token_type=recovery"))
        #expect(!RecoveryLink.isRecovery(url))
    }
}
