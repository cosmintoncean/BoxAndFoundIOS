import CryptoKit
import Foundation

/// The nonce pair Sign in with Apple needs.
///
/// Apple's request carries the SHA-256 *hash* of a nonce; the ID token it
/// returns embeds that hash; GoTrue is then given the raw value and rehashes
/// it to prove the token was minted for this request and not replayed. So the
/// app has to hold both halves between the button tap and the completion, and
/// they must not be regenerated in between.
enum AppleNonce {

    /// Unreserved URL characters, so the value survives the round trip through
    /// Apple's request without any encoding of its own.
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~")

    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// Lowercase hex, which is the form Apple's documentation and every GoTrue
    /// example use. Case matters: the hash is compared as a string.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
