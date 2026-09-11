import SwiftUI

/// The one place that decides signed-in from signed-out.
struct RootView: View {
    let presenter: RootPresenter

    var body: some View {
        ZStack {
            Color.bfBg.ignoresSafeArea()
            content
        }
        .tint(.bfAccent)
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.viewState.content {
        case .loading:
            ProgressView()
        case .signedOut:
            AuthView()
        case .passwordReset:
            PasswordResetView { presenter.passwordResetFinished() }
        case .signedIn(let userID, let pendingInviteCode):
            InventoryView(
                userID: userID,
                pendingInviteCode: pendingInviteCode,
                onInviteConsumed: { presenter.inviteConsumed() },
                signOut: { await presenter.signOutTapped() }
            )
        }
    }
}
