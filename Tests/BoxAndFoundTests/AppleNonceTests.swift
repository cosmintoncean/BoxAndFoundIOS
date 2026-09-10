import Testing
@testable import BoxAndFound

@Suite("Sign in with Apple nonce")
struct AppleNonceTests {

    @Test("Hashes match the published SHA-256 vectors")
    func knownVectors() {
        #expect(AppleNonce.sha256("abc")
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(AppleNonce.sha256("")
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("The hash is lowercase hex, which is what GoTrue compares against")
    func lowercaseHex() {
        let hash = AppleNonce.sha256(AppleNonce.random())
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("Nonces are the requested length and survive a URL round trip unencoded")
    func shape() {
        #expect(AppleNonce.random().count == 32)
        #expect(AppleNonce.random(length: 7).count == 7)

        let unreserved = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~")
        #expect(AppleNonce.random(length: 256).allSatisfy { unreserved.contains($0) })
    }

    @Test("Two nonces are not the same nonce")
    func distinct() {
        let many = Set((0..<50).map { _ in AppleNonce.random() })
        #expect(many.count == 50)
    }
}
