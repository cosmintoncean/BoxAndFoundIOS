import Foundation
import Observation

/// Decides signed-in from signed-out, mirroring the Android `RootScreen`.
///
/// Owns the `SessionStore` rather than reading it from the environment: the
/// session is what this screen is *about*, and one owner is easier to follow
/// than an ambient one.
@MainActor
@Observable
final class RootPresenter: Presenter {

    private let session: SessionStore
    private let repository: AuthRepository

    /// Set the moment a recovery link is opened, before the session it
    /// carries has been redeemed — otherwise the app would show the inventory
    /// for the instant between the two.
    private var isResettingPassword = false

    /// An invite the app was opened with, parked until there is a screen able
    /// to act on it. A link can arrive before there is anywhere to send it: on
    /// a cold start the session is still being restored, and an invite tapped
    /// while signed out has to wait for sign-in.
    private var pendingInviteCode: String?

    init(session: SessionStore = SessionStore(), repository: AuthRepository = AuthRepository()) {
        self.session = session
        self.repository = repository
    }

    var viewState: RootViewState {
        if isResettingPassword { return RootViewState(content: .passwordReset) }
        // Explicit: the guard above makes this a multi-statement body, so the
        // switch expression no longer returns on its own.
        return switch session.state {
        case .restoring:
            RootViewState(content: .loading)
        case .signedOut:
            RootViewState(content: .signedOut)
        case .signedIn(let user):
            RootViewState(content: .signedIn(userID: user.id, pendingInviteCode: pendingInviteCode))
        }
    }

    func start() {
        session.start()
    }

    /// Every link the app is opened with lands here.
    ///
    /// OAuth does not: `ASWebAuthenticationSession` hands its callback
    /// straight back to the SDK inside the call that started it. A reset link
    /// is opened by Mail instead, so this is the only place it can be caught.
    func opened(_ url: URL) async {
        // An invite is not a recovery link and carries no session, so it is
        // parked rather than redeemed.
        if case .invite(let code, _) = InviteLink.parse(url.absoluteString) {
            pendingInviteCode = code
            return
        }
        guard RecoveryLink.isRecovery(url) else { return }
        isResettingPassword = true
        // A spent or expired link leaves no session. The reset screen still
        // goes up, and GoTrue reports the refusal there when they try to save
        // — better than a link that silently does nothing.
        try? await repository.completeRecovery(from: url)
    }

    /// The new password is set, or they backed out. Either way this screen is
    /// done and the session decides again.
    /// Acted on exactly once: without this, coming back to the box list
    /// would re-open the invite it had just dealt with.
    func inviteConsumed() {
        pendingInviteCode = nil
    }

    func passwordResetFinished() {
        isResettingPassword = false
    }

    func signOutTapped() async {
        await session.signOut()
    }
}
