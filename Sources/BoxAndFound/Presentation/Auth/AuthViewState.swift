import Foundation

/// Everything `AuthView` draws, and nothing it does not.
///
/// A UI model: no `AuthFailure`, no `OAuthProvider`, no Supabase type. By the
/// time a failure reaches here it is already a sentence, and the decision to
/// show it at all has already been made.
///
/// The boundary is *varying* content, not every string on screen. Field labels
/// that never change ("Email", "you@example.com") stay in the view, where
/// static text belongs; anything the presenter can alter — titles that follow
/// the mode, values, enablement, notices — lives here, so a test can read it.
struct AuthViewState: Equatable {

    enum Mode: Equatable, Identifiable, CaseIterable {
        case signIn, signUp
        var id: Self { self }
    }

    struct ModeOption: Equatable, Identifiable {
        let mode: Mode
        let title: String
        var id: Mode { mode }
    }

    struct Notice: Equatable {
        enum Kind: Equatable { case error, success }
        let kind: Kind
        let text: String
    }

    struct ProviderButton: Equatable, Identifiable {
        /// The presentation layer's own vocabulary. Keeping it separate from
        /// `OAuthProvider` is what stops a domain type reaching the view; the
        /// presenter owns the translation both ways.
        enum Kind: Equatable { case apple, google, facebook }

        let kind: Kind
        let title: String
        var id: Kind { kind }
    }

    var mode: Mode
    var modes: [ModeOption]
    var heading: String

    var name: String
    var isNameFieldVisible: Bool
    var email: String
    var password: String
    var isPasswordVisible: Bool
    /// Shown under the password field while signing up, nil while signing in.
    var passwordHint: String?

    var submitTitle: String
    var isSubmitEnabled: Bool
    var isSubmitting: Bool

    var notice: Notice?
    var providers: [ProviderButton]
}
