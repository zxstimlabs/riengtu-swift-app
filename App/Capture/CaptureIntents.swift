import AppIntents
import RiengtuKit

/// Forwards a bank's notification, email or message to the inbox as it came, for money out or in.
/// Made for a Shortcuts automation that runs when the bank's notification or email arrives, so QR
/// transfers, card payments and money received are captured without opening the app. Runs in the
/// background, even while the device is locked, and only forwards, so it's quick: the app reads
/// the message when it's open (`InboxStore.readNewItems()`).
struct CaptureBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Bank Message to Inbox"
    static let description = IntentDescription(
        // Apple rejects a build whose intent descriptions say "Apple" (ITMS-90626), so not "Apple Intelligence".
        "Puts a bank’s notification, email or message about money sent or received, such as a QR transfer, in the inbox. Riêng Tư reads it when you open the app, for you to add to the ledger."
    )

    /// Optional, because a required parameter without a value makes the action ask for one, which
    /// fails in an automation ("This action could not be run with the current user interface"),
    /// such as when the notification gives no text.
    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String?

    @AppDependency private var inbox: InboxStore

    /// Only in the background: it never needs the screen.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$message) to the inbox")
    }

    /// Says nothing: a notification automation can't show a reply, and fails or times out
    /// trying ("This action could not be run with the current user interface"). The inbox's badge
    /// shows it arrived.
    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try inbox.capture(message: message ?? "")
        return .result()
    }
}

/// Puts a payment whose amount is known in the inbox. Made for a Shortcuts automation that runs
/// when the person pays with a card in Wallet (Apple Pay).
struct CapturePaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Payment to Inbox"
    static let description = IntentDescription(
        // Apple rejects a build whose intent descriptions say "Apple" (ITMS-90626), so not "Apple Pay".
        "Puts a payment in the inbox to add as an expense, such as one from an automation that runs when you pay with a card in Wallet."
    )

    /// Text, read by `TransactionText.amount`, because Wallet passes the amount as text with its
    /// currency, such as "45.000 ₫". As a currency amount, Shortcuts had to turn that into a
    /// number, and often passed nothing instead.
    ///
    /// Optional, because a required parameter without a value makes the action ask for one, which
    /// fails in an automation that runs in the background. Wallet doesn't always pass the amount on.
    @Parameter(title: "Amount")
    var amount: String?

    @Parameter(title: "Merchant")
    var merchant: String?

    @AppDependency private var inbox: InboxStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) at \(\.$merchant) to the inbox")
    }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try inbox.capturePayment(amount: amount, merchant: merchant ?? "")
        return .result()
    }
}
