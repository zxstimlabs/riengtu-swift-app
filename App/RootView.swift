import RiengtuKit
import SwiftUI

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(AppLock.self) private var lock
    @Environment(InboxStore.self) private var inbox
    @Environment(BackgroundReading.self) private var backgroundReading
    @Environment(\.scenePhase) private var scenePhase

    @SceneStorage("tab") private var tab = AppTab.inbox
    @AppStorage(InboxHistoryDuration.key) private var historyDays = InboxHistoryDuration.standard.rawValue

    var body: some View {
        Group {
            switch store.status {
            case .ready:
                TabView(selection: $tab) {
                    // What waits to be added, where most transactions come from, first: from left
                    // to right, the inbox feeds the ledger.
                    Tab("Inbox", systemImage: "tray", value: .inbox) {
                        NavigationStack { InboxView() }
                    }
                    .badge(inbox.pending.count)
                    Tab("Ledger", systemImage: "book.closed", value: .ledger) {
                        NavigationStack { LedgerView() }
                    }
                    Tab("Assets", systemImage: "chart.pie", value: .assets) {
                        NavigationStack { AssetsView() }
                    }
                }
                // A sidebar on the iPad, which people can hide.
                .tabViewStyle(.sidebarAdaptable)
            case .notLoaded:
                // The data can't be read while the device is locked. It loads once Riengtu is
                // active. If it still can't then, say so, rather than show nothing.
                if store.loadFailed, scenePhase == .active {
                    NavigationStack { NotOpenedView() }
                } else {
                    Color.clear
                }
            case .unreadable:
                NavigationStack { UnreadableDataView() }
            }
        }
        .privacyShield()
        .onChange(of: scenePhase == .active ? inbox.unreadCount : 0, initial: true) { _, unread in
            // New bank messages are read while the app is open, with Apple Intelligence where
            // it's available, which takes a few seconds each, so a screen shows how it's going.
            guard unread > 0 else { return }
            // A few read in moments, and without Apple Intelligence the rules take no time. More
            // wait for the person to start them on the Inbox tab, so they can go on in the
            // background.
            if unread < ReadingView.minimumCount || ExpenseTagger.availability != .available {
                inbox.startReading()
            }
        }
        #if os(iOS)
        .onChange(of: inbox.isReading && scenePhase == .active, initial: true) { _, keepsAwake in
            // The screen stays on while it reads, so the person can put the iPhone down. In the
            // foreground the model also reads without the limits iOS sets in the background.
            UIApplication.shared.isIdleTimerDisabled = keepsAwake
        }
        #endif

        .onChange(of: store.status == .ready && store.ledger.needsStarterTags, initial: true) { _, needsThem in
            // Once, and again after erasing everything.
            if needsThem { try? store.addStarterTags() }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                store.load()
                // Shortcuts may have added payments while the app was closed.
                inbox.load()
                try? inbox.deleteHistory(handledBefore: InboxHistoryDuration.days(historyDays).cutoff(from: .now))
                sync.start()
            case .background:
                // The database can't be opened once the device locks, so syncing waits until
                // Riêng Tư is open again.
                sync.stop()
                // Unless iOS lets reading go on in the background.
                if !backgroundReading.isRunning { inbox.stopReading() }
                lock.lock()
            default:
                break
            }
        }
        .onChange(of: store.status) { _, status in
            if status == .ready, scenePhase == .active { sync.start() }
        }
        #if os(iOS)
        .onChange(of: sync.isEnabled, initial: true) { _, isEnabled in
            // iCloud tells the sync engine about other devices' changes with a push.
            if isEnabled { UIApplication.shared.registerForRemoteNotifications() }
        }
        #endif
    }
}

private enum AppTab: String {
    case inbox, ledger, assets
}

/// Shown when the data couldn't be opened, though it isn't damaged.
private struct NotOpenedView: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Can’t Open Your Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Riêng Tư couldn’t open your data just now. Nothing was changed. Try again, and if this keeps happening, restart your device.")
        } actions: {
            Button("Try Again") { store.load() }
                .buttonStyle(.borderedProminent)
        }
    }
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
        .confirmationDialog("Start over with an empty ledger?", isPresented: $confirmsStartingOver, titleVisibility: .visible) {
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
