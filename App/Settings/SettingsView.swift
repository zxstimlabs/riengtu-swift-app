import RiengtuKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

    /// The language the app is showing, which iOS picks from the ones it has.
    private let language = AppLanguage.preferred(from: Bundle.main.preferredLocalizations)

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
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
                LabeledContent("Version", value: version)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
