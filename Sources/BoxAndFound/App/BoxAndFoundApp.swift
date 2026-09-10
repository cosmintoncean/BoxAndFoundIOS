import SwiftUI

@main
struct BoxAndFoundApp: App {
    @State private var presenter = RootPresenter()

    var body: some Scene {
        WindowGroup {
            RootView(presenter: presenter)
                .task { presenter.start() }
        }
    }
}
