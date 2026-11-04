import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
        }
    }
}

#Preview("English") {
    RootView()
}

#Preview("Vietnamese") {
    RootView()
        .environment(\.locale, Locale(identifier: "vi"))
}
