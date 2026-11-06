import AppIntents
import AppIntentsTesting
import XCTest

/// Runs the capture actions the way Shortcuts does: through the system, which launches the app
/// in the background. Needs an iOS 27.2 or later simulator with the app installed and launched
/// once, so the system has registered its actions (README).
///
/// The actions write to the simulator's real inbox, so its items pile up there.
final class CaptureIntentTests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "vn.riengtu")

    func testCapturesABankMessage() async throws {
        let intent = definitions.intents["CaptureBankMessageIntent"].makeIntent(
            message: "Số tiền: -150,000 VND\nNội dung: INTENT TEST"
        )
        try await intent.run()
    }

    func testCapturesAnEmptyMessageWithoutFailing() async throws {
        try await definitions.intents["CaptureBankMessageIntent"].makeIntent(message: "").run()
    }

    func testCapturesAPayment() async throws {
        let intent = definitions.intents["CapturePaymentIntent"].makeIntent(
            amount: IntentCurrencyAmount(amount: 45_000, currencyCode: "VND"),
            merchant: "Intent Test"
        )
        try await intent.run()
    }

    /// An automation runs in the background, where the action can't ask for a missing amount,
    /// such as when Wallet doesn't pass one on.
    func testCapturesAPaymentWithoutAnAmountOrMerchant() async throws {
        try await definitions.intents["CapturePaymentIntent"].makeIntent(amount: nil, merchant: nil).run()
    }
}
