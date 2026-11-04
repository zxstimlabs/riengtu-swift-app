import RiengtuKit
import SwiftUI

@main
struct RiengtuApp: App {
    @State private var store = LedgerStore(file: .applicationSupport)
    @State private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
        }
    }
}
