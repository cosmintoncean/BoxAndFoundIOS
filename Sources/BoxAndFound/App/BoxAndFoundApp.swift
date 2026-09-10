import SwiftUI

@main
struct BoxAndFoundApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { session.start() }
        }
    }
}
