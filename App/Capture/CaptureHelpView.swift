import SwiftUI

/// How to set up Shortcuts automations that send payments to the inbox. iOS doesn't let an app
/// read other apps' notifications, but Shortcuts can pass on a bank's emails and Apple Pay
/// payments.
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
                Text("Riengtu can’t see other apps’ notifications, but Shortcuts can send it your bank’s emails and your Apple Pay payments. They wait in the inbox until you add or dismiss them.")
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
