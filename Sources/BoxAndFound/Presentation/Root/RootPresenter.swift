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

    init(session: SessionStore = SessionStore()) {
        self.session = session
    }

    var viewState: RootViewState {
        switch session.state {
        case .restoring:
            RootViewState(content: .loading)
        case .signedOut:
            RootViewState(content: .signedOut)
        case .signedIn(let user):
            // M2 replaces this with the inventory.
            RootViewState(content: .signedIn(
                title: user.email ?? "Signed in",
                subtitle: user.isPremium ? "Premium" : "Free"
            ))
        }
    }

    func start() {
        session.start()
    }

    func signOutTapped() async {
        await session.signOut()
    }
}
