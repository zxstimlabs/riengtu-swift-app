import AppIntents
import RiengtuKit
import SwiftUI

@main
struct RiengtuApp: App {
    @State private var store = LedgerStore(file: .applicationSupport)
    @State private var lock = AppLock()
    @State private var inbox: InboxStore

    init() {
        let inbox = InboxStore(file: .applicationSupport)
        _inbox = State(initialValue: inbox)
        // The Shortcuts actions put payments in this same inbox, so they show at once when the
        // app is open.
        AppDependencyManager.shared.add(dependency: inbox)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(inbox)
        }
    }
}
