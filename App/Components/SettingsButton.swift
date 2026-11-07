import SwiftUI

extension View {
    /// The gear at the top left of each tab, which opens Settings as a page in the tab's
    /// navigation stack. Each tab's own add button is at the top right.
    func settingsButton() -> some View {
        modifier(SettingsButton())
    }
}

private struct SettingsButton: ViewModifier {
    @State private var showsSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Settings", systemImage: "gear") { showsSettings = true }
                }
            }
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView()
            }
    }
}
