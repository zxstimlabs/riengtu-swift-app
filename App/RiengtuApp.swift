import AppIntents
import RiengtuKit
import SwiftUI

@main
struct RiengtuApp: App {
    @State private var store: LedgerStore
    @State private var sync: CloudSync
    @State private var lock = AppLock()
    @State private var inbox: InboxStore
    @State private var backgroundReading = BackgroundReading()

    init() {
        let store = LedgerStore(location: .applicationSupport)
        _store = State(initialValue: store)
        _sync = State(initialValue: CloudSync(store: store))
        let inbox = InboxStore(location: .applicationSupport)
        _inbox = State(initialValue: inbox)
        // The Shortcuts actions put payments in this same inbox, so they show at once when the
        // app is open.
        AppDependencyManager.shared.add(dependency: inbox)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .environment(lock)
                .environment(inbox)
                .environment(backgroundReading)
        }
    }
}
