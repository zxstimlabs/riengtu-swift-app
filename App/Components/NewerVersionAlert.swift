import SwiftUI

extension View {
    /// Says that what the person tapped was saved by a later version of Riêng Tư on another device,
    /// so this one shows it but doesn't change it.
    func newerVersionAlert(isPresented: Binding<Bool>) -> some View {
        alert("Saved by a Newer Version", isPresented: isPresented) {
            Button("OK") {}
        } message: {
            Text("Update Riêng Tư on this device to change this.")
        }
    }
}
