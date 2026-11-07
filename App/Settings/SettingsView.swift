import RiengtuKit
import SwiftUI

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(InboxStore.self) private var inbox
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @State private var confirmsErasing = false
    @State private var eraseFailed = false
    @State private var iCloudEraseFailed = false
    @AppStorage(Self.suggestsTagsKey) private var suggestsTags = true
    @AppStorage(InboxHistoryDuration.key) private var historyDays = InboxHistoryDuration.standard.rawValue

    /// Whether Apple Intelligence suggests tags and categories for expenses in the editor. A setting,
    /// not spending data, so it can live in `UserDefaults`.
    static let suggestsTagsKey = "suggestsTags"

    /// The language the app is showing, which iOS picks from the ones it has.
    private let language = AppLanguage.preferred(from: Bundle.main.preferredLocalizations)

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        let method = lock.method
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { lock.isEnabled },
                    set: { enabled in Task { await lock.setEnabled(enabled) } }
                )) {
                    switch method {
                    case .faceID: Text("Lock with Face ID")
                    case .touchID: Text("Lock with Touch ID")
                    case .opticID: Text("Lock with Optic ID")
                    case .passcode, .unavailable: Text("Lock with Passcode")
                    }
                }
                .disabled(method == .unavailable && !lock.isEnabled)
            } header: {
                Text("Privacy")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if method == .unavailable {
                        Text("To lock Riengtu, set a passcode for this device.")
                    }
                    if sync.isEnabled {
                        Text("Riêng Tư has no account of its own. Your ledger and assets are on this device, in its backups, and in your iCloud account, encrypted end to end.")
                    } else {
                        Text("Riengtu has no account and doesn’t connect to the internet. Your ledger and assets are stored only on this device and in its backups.")
                    }
                }
            }

            syncSection

            tagsSection

            Section {
                NavigationLink("Capture Payments") {
                    CaptureHelpView()
                }
                NavigationLink("Inbox History") {
                    InboxHistoryView()
                }
                Picker("Keep History", selection: $historyDays) {
                    ForEach(InboxHistoryDuration.allCases) { duration in
                        Text(duration.name).tag(duration.rawValue)
                    }
                }
            } header: {
                Text("Inbox")
            } footer: {
                Text("Send your bank’s notifications and emails, and your Apple Pay payments, to the inbox with Shortcuts. What you add or dismiss stays in the history with its message, then it’s deleted.")
            }
            .onChange(of: historyDays) { _, days in
                try? inbox.deleteHistory(handledBefore: InboxHistoryDuration.days(days).cutoff(from: .now))
            }

            Section {
                LabeledContent("Language", value: language.endonym)
                #if os(iOS)
                // iOS keeps each app's language in its page in Settings, not in the app.
                Button("Change Language") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                #endif
            } footer: {
                Text("Riengtu uses your device’s language. You can choose a different language for Riengtu in Settings.")
            }

            Section {
                Button("Erase All Data", role: .destructive) {
                    confirmsErasing = true
                }
                .disabled(store.ledger.entries.isEmpty && store.ledger.assets.isEmpty && store.ledger.tags.isEmpty && inbox.items.isEmpty)
            }

            Section {
                LabeledContent("Version", value: version)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Erase your ledger and assets?", isPresented: $confirmsErasing, titleVisibility: .visible) {
            Button("Erase All Data", role: .destructive) {
                Task { await eraseAll() }
            }
        } message: {
            if sync.isEnabled {
                Text("This deletes every transaction and asset from this device and from iCloud. Your other devices keep theirs and stop syncing. You can’t undo this.")
            } else {
                Text("This deletes every transaction and asset from this device. You can’t undo this.")
            }
        }
        .alert("Couldn’t Erase", isPresented: $iCloudEraseFailed) {
            Button("OK") {}
        } message: {
            Text("Riêng Tư couldn’t erase your data in iCloud, so nothing was erased. Check your connection and try again.")
        }
        .alert("Couldn’t Save", isPresented: $eraseFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
        }
    }

    /// Erases iCloud first, so nothing is erased if that fails.
    private func eraseAll() async {
        if sync.isEnabled {
            do {
                try await sync.eraseICloudData()
            } catch {
                iCloudEraseFailed = true
                sync.start()
                return
            }
        }
        do {
            try store.eraseAll()
            try inbox.removeAll()
        } catch {
            eraseFailed = true
        }
        sync.start()
    }

    private var syncSection: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in Task { await sync.setEnabled(enabled) } }
            ))
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                switch sync.status {
                case .off:
                    EmptyView()
                case .syncing:
                    Text("Syncing…")
                case .upToDate(let date):
                    Text("Synced \(date, format: .relative(presentation: .named)).")
                case .noAccount:
                    Text("To sync, sign in to iCloud in Settings.")
                case .accountChanged:
                    Text("Syncing turned off because this device’s iCloud account changed. What’s on this device is kept.")
                case .deletedFromICloud:
                    Text("Syncing turned off because your data was erased from iCloud, such as on another device. What’s on this device is kept.")
                case .failed:
                    Text("Couldn’t sync just now. Riêng Tư will try again.")
                }
                Text("Keeps your ledger and assets on each of your devices with Riêng Tư, through your iCloud account. They’re encrypted end to end, so only your devices can read them.")
            }
        }
    }

    private var tagsSection: some View {
        let availability = ExpenseTagger.availability
        return Section {
            NavigationLink {
                TagsView()
            } label: {
                LabeledContent("Tags") {
                    Text(store.ledger.tags.count, format: .number)
                }
            }
            if availability != .unsupported {
                Toggle("Suggest with Apple Intelligence", isOn: $suggestsTags)
                    .disabled(availability != .available)
            }
        } footer: {
            switch availability {
            case .available:
                Text("Apple Intelligence suggests a category and tags from an expense’s note. It runs on this device, so your notes never leave it.")
            case .appleIntelligenceOff:
                Text("To get suggestions for tags and categories, turn on Apple Intelligence in Settings.")
            case .notReady:
                Text("Apple Intelligence is getting ready. Suggestions start once it’s downloaded.")
            case .unsupported:
                EmptyView()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
