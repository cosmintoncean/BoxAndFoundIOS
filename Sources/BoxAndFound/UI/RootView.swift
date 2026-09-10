import SwiftUI

/// The one place that decides signed-in from signed-out, mirroring the Android
/// client's `RootScreen`.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Color.bfBg.ignoresSafeArea()
            content
        }
        .tint(.bfAccent)
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .restoring:
            ProgressView()
        case .signedOut:
            AuthView()
        case .signedIn(let user):
            // M2 replaces this with the inventory.
            PlaceholderView(
                title: user.email ?? "Signed in",
                detail: user.isPremium ? "Premium" : "Free"
            )
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Color.bfText)
            Text(detail).font(.subheadline).foregroundStyle(Color.bfTextMuted)
        }
    }
}
