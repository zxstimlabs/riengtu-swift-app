import AppIntents
import RiengtuKit

/// Puts a bank's email or message in the inbox. Made for a Shortcuts automation that runs when
/// the bank's email arrives, so QR transfers and card payments are captured without opening the
/// app. Runs in the background, even while the device is locked.
struct CaptureBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Bank Message to Inbox"
    static let description = IntentDescription(
        "Reads a bank’s email or message about a payment, such as a QR transfer, and puts it in the inbox to add as an expense. Money received is left out."
    )

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    @AppDependency private var inbox: InboxStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$message) to the inbox")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: CaptureDialog.for(try inbox.capture(message: message)))
    }
}

/// Puts a payment whose amount is known in the inbox. Made for a Shortcuts automation that runs
/// when the person pays with Apple Pay.
struct CapturePaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Payment to Inbox"
    static let description = IntentDescription(
        "Puts a payment in the inbox to add as an expense, such as one from an automation that runs when you pay with Apple Pay."
    )

    @Parameter(title: "Amount")
    var amount: IntentCurrencyAmount

    @Parameter(title: "Merchant")
    var merchant: String?

    @AppDependency private var inbox: InboxStore

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) at \(\.$merchant) to the inbox")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try inbox.capturePayment(amount: amount.amount, currencyCode: amount.currencyCode, merchant: merchant ?? "")
        return .result(dialog: CaptureDialog.for(result))
    }
}

/// What an action says it did. No amounts or names, since it can show on the Lock Screen.
private enum CaptureDialog {
    static func `for`(_ result: InboxStore.CaptureResult) -> IntentDialog {
        switch result {
        case .added: "Added to the inbox."
        case .moneyIn: "That was money received, so it wasn’t added."
        case .duplicate: "That’s already in the inbox."
        case .empty: "There was nothing to add."
        }
    }
}
