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
        case .signedIn(let title, let subtitle):
            VStack(spacing: 8) {
                Text(title).font(.headline).foregroundStyle(Color.bfText)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.bfTextMuted)
                Button("Sign out") {
                    Task { await presenter.signOutTapped() }
                }
                .padding(.top, 12)
            }
        }
    }
}
