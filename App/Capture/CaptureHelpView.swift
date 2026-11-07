import SwiftUI

/// How to set up Shortcuts automations that send payments to the inbox. iOS doesn't let an app
/// read other apps' notifications, but Shortcuts can forward a bank app's notifications (iOS 27),
/// a bank's emails, and Apple Pay payments.
struct CaptureHelpView: View {
    /// The shortcut "When Any Card is tapped" → Add Payment to Inbox, with the tap's Amount and
    /// Merchant, shared from iCloud. From iOS 27 a shared shortcut carries its trigger, so adding
    /// it is all the setup. The link is a copy: after changing the shortcut or the action's
    /// parameters, share it again and replace the link.
    static let cardPaymentShortcut = URL(string: "https://www.icloud.com/shortcuts/c2c4ce2620e746fe83bfe4bce4ead8bc")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Text("Riêng Tư can’t see other apps’ notifications itself, but Shortcuts can forward it your bank’s notifications and emails, and your Apple Pay payments. They wait in the inbox, where Riêng Tư reads them when you open it, until you add or dismiss them.")
            }

            if #available(iOS 27, *) {
                Section {
                    Step(1, "In Shortcuts, tap Automation, then the Add button, and choose Notification.")
                    Step(2, "Choose your bank’s app. To leave out its offers, add a filter that only its transactions match, such as Title contains VND.")
                    Step(3, "Choose Run Immediately, tap Next, then New Blank Automation, and add the action Add Bank Message to Inbox.")
                    // The whole notification, as the user set it up: Shortcuts gives its title and body.
                    Step(4, "Tap Message in the action, and choose Shortcut Input.")
                } header: {
                    Text("Bank App Notifications")
                } footer: {
                    Text("Set up one for each bank. With Apple Intelligence, Riêng Tư reads each one for the amount, whether it’s spending, income or a transfer, and its category.")
                }
            }

            Section {
                if #available(iOS 27, *) {
                    Button("Add Card Payment Shortcut") {
                        openURL(Self.cardPaymentShortcut)
                    }
                } else {
                    Step(1, "In Shortcuts, tap Automation, then the Add button, and choose Transaction.")
                    Step(2, "Choose your cards, choose Run Immediately, and tap Next.")
                    Step(3, "Tap New Blank Automation, and add the action Add Payment to Inbox.")
                    Step(4, "Set its amount and merchant to the Shortcut Input’s Amount and Merchant.")
                }
            } header: {
                Text("Apple Pay")
            } footer: {
                if #available(iOS 27, *) {
                    Text("Opens Shortcuts to add a shortcut that puts each payment with a card in Wallet in the inbox.")
                } else {
                    Text("For payments with a card in Wallet.")
                }
            }

            Section {
                Step(1, "In Shortcuts, tap Automation, then the Add button, and choose Email.")
                Step(2, "Choose your bank’s email address as the sender, choose Run Immediately, and tap Next.")
                Step(3, "Tap New Blank Automation, and add the action Add Bank Message to Inbox.")
                Step(4, "Tap Message in the action, and choose Shortcut Input.")
            } header: {
                Text("Bank Emails")
            } footer: {
                Text("For QR transfers, card payments and money received that your bank emails you about. The emails need to arrive in the Mail app.")
            }

            Section {
                Text("To add transactions from before, take screenshots of your bank app’s transaction history, each transaction whole on at least one, with its day’s heading if you can. Then in the Inbox, tap the Add button and choose From Photos.")
            } header: {
                Text("Past Transactions")
            } footer: {
                Text("Riêng Tư reads the screenshots on this device, and leaves out transactions already in the inbox.")
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
