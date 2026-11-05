import SwiftUI

/// How to set up Shortcuts automations that send payments to the inbox. iOS doesn't let an app
/// read other apps' notifications, but Shortcuts can pass on a bank's emails and Apple Pay
/// payments.
struct CaptureHelpView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Text("Riengtu can’t see other apps’ notifications, but Shortcuts can send it your bank’s emails and your Apple Pay payments. They wait in the inbox until you add or dismiss them.")
            }

            Section {
                Step(1, "In Shortcuts, tap Automation, then the Add button, and choose Email.")
                Step(2, "Choose your bank’s email address as the sender, choose Run Immediately, and tap Next.")
                Step(3, "Tap New Blank Automation, and add the action Add Bank Message to Inbox.")
                Step(4, "Tap Message in the action, and choose Shortcut Input.")
            } header: {
                Text("Bank Emails")
            } footer: {
                Text("For QR transfers and card payments your bank emails you about. The emails need to arrive in the Mail app. Money received is left out.")
            }

            Section {
                Step(1, "In Shortcuts, tap Automation, then the Add button, and choose Transaction.")
                Step(2, "Choose your cards, choose Run Immediately, and tap Next.")
                Step(3, "Tap New Blank Automation, and add the action Add Payment to Inbox.")
                Step(4, "Set its amount and merchant to the Shortcut Input’s Amount and Merchant.")
            } header: {
                Text("Apple Pay")
            } footer: {
                Text("For payments with a card in Wallet.")
            }

            Section {
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                }
            }
        }
        .navigationTitle("Capture Payments")
    }
}

/// A numbered step.
private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}

#Preview {
    NavigationStack {
        CaptureHelpView()
    }
}
