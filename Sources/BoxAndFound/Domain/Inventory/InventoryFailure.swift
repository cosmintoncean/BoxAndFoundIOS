import Foundation

/// Why a read of the inventory did not produce one.
///
/// Narrower than `AuthFailure` on purpose: a household read has far fewer
/// interesting ways to fail, and every one of them ends in the same two
/// questions — is this worth a retry button, and what does it say.
enum InventoryFailure: Error, Equatable, Sendable {
    case network
    case notFound
    case unknown(detail: String?)
}
