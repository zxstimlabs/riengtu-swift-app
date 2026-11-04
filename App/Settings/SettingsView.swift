import RiengtuKit
import SwiftUI

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL
    @State private var confirmsErasing = false
    @State private var eraseFailed = false

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
                .disabled(store.ledger.expenses.isEmpty && store.ledger.assets.isEmpty)
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
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .previewEnvironment()
}
