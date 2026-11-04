import SwiftUI

struct HomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Welcome to Riengtu", systemImage: "lock.shield")
        } description: {
            Text("Your app starts here.")
        }
    }
}

#Preview {
    HomeView()
}
