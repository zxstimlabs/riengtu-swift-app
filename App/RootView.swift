import RiengtuKit
import SwiftUI

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    @SceneStorage("tab") private var tab = AppTab.spending

    var body: some View {
        Group {
            switch store.status {
            case .ready:
                TabView(selection: $tab) {
                    Tab("Spending", systemImage: "list.bullet.rectangle.portrait", value: .spending) {
                        NavigationStack { SpendingView() }
                    }
                    Tab("Assets", systemImage: "chart.pie", value: .assets) {
                        NavigationStack { AssetsView() }
                    }
                    Tab("Settings", systemImage: "gear", value: .settings) {
                        NavigationStack { SettingsView() }
                    }
                }
                // A sidebar on the iPad, which people can hide.
                .tabViewStyle(.sidebarAdaptable)
            case .notLoaded:
                // The data can't be read while the device is locked. It loads once Riengtu is
                // active.
                Color.clear
            case .unreadable:
                NavigationStack { UnreadableDataView() }
            }
        }
        .privacyShield()
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: store.load()
            case .background: lock.lock()
            default: break
            }
        }
    }
}

private enum AppTab: String {
    case spending, assets, settings
}

/// Shown when the saved data is damaged, or from a later version of Riengtu.
private struct UnreadableDataView: View {
    @Environment(LedgerStore.self) private var store
    @State private var confirmsStartingOver = false

    var body: some View {
        ContentUnavailableView {
            Label("Can’t Open Your Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Riengtu can’t read the data saved on this device. It may be from a newer version of Riengtu, so try updating the app.")
        } actions: {
            Button("Start Over") { confirmsStartingOver = true }
        }
        .confirmationDialog("Start over with no expenses?", isPresented: $confirmsStartingOver, titleVisibility: .visible) {
            Button("Start Over", role: .destructive) {
                try? store.startOver()
            }
        } message: {
            Text("Riengtu keeps the unreadable data on this device but won’t show it.")
        }
    }
}

#Preview("English") {
    RootView()
        .previewEnvironment()
}

#Preview("Vietnamese") {
    RootView()
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: "vi"))
}
