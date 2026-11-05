import RiengtuKit
import SwiftUI

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(InboxStore.self) private var inbox
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @State private var confirmsErasing = false
    @State private var eraseFailed = false
    @AppStorage(Self.suggestsTagsKey) private var suggestsTags = true

    /// Whether Apple Intelligence suggests tags and categories in the expense editor. A setting,
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
                    Text("Riengtu has no account and doesn’t connect to the internet. Your spending and assets are stored only on this device and in its backups.")
                }
            }

            tagsSection

            Section {
                NavigationLink("Capture Payments") {
                    CaptureHelpView()
                }
            } footer: {
                Text("Send your bank’s emails and your Apple Pay payments to the inbox with Shortcuts.")
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
                .disabled(store.ledger.expenses.isEmpty && store.ledger.assets.isEmpty && store.ledger.tags.isEmpty && inbox.items.isEmpty)
            }

            Section {
                LabeledContent("Version", value: version)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Erase all your expenses and assets?", isPresented: $confirmsErasing, titleVisibility: .visible) {
            Button("Erase All Data", role: .destructive) {
                do {
                    try store.eraseAll()
                    try inbox.removeAll()
                } catch {
                    eraseFailed = true
                }
            }
        } message: {
            Text("This deletes every expense and asset from this device. You can’t undo this.")
        }
        .alert("Couldn’t Save", isPresented: $eraseFailed) {
            Button("OK") {}
        } message: {
            Text("Riengtu couldn’t save your change. Try again.")
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
