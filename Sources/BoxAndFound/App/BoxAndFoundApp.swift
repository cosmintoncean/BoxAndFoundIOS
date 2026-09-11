import SwiftUI

@main
struct BoxAndFoundApp: App {
    @State private var presenter = RootPresenter.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView(presenter: presenter)
                .task { presenter.start() }
                .onOpenURL { url in
                    Task { await presenter.opened(url) }
                }
        }
    }
}

extension RootPresenter {
    /// Production wiring, unless a UI test asked for fixtures.
    ///
    /// The check lives here rather than inside `RootPresenter` so the
    /// presenter stays a presenter: this is the composition root deciding what
    /// to build, which is the one place allowed to care.
    @MainActor
    static func forLaunch() -> RootPresenter {
        #if DEBUG
        if UITestFixtures.isEnabled {
            return RootPresenter(session: UITestFixtures.install())
        }
        #endif
        return RootPresenter()
    }
}
