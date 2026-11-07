import AppIntents
import AppIntentsTesting
import XCTest

/// Runs the capture actions the way Shortcuts does: through the system, which launches the app
/// in the background. Needs an iOS 27.2 or later simulator with the app installed and launched
/// once, so the system has registered its actions (README).
///
/// The actions write to the simulator's real inbox, so its items pile up there, and a bank
/// message that's already there or in the history isn't added again.
final class CaptureIntentTests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "vn.riengtu")

    func testCapturesABankMessage() async throws {
        let intent = definitions.intents["CaptureBankMessageIntent"].makeIntent(
            message: "Số tiền: -150,000 VND\nNội dung: INTENT TEST"
        )
        try await intent.run()
    }

    /// A bank app's notification, title then body, as the notification automation forwards it.
    func testForwardsABankNotification() async throws {
        for message in [
            "- VND 25,000\nTài khoản: 1234567890\nSố dư: VND 16,181,570\nNGUYEN VAN AN chuyen tien. Ma tham chieu 123456",
            "- VND 2,042,000\nTài khoản: 1234567890\nSố dư: VND 16,206,570\nThanh toan no the tin dung _ So tien 2042000 VND _ Ngay 05/11/2026",
            "+ VND 1,890\nTing ting! Lợi nhuận Sinh lời tự động đã về",
        ] {
            try await definitions.intents["CaptureBankMessageIntent"].makeIntent(message: message).run()
        }
    }

    func testCapturesAnEmptyMessageWithoutFailing() async throws {
        try await definitions.intents["CaptureBankMessageIntent"].makeIntent(message: "").run()
    }

    /// As when a notification gives no text, or the shortcut runs without one: the action can't
    /// ask for a message in an automation.
    func testCapturesNoMessageWithoutFailing() async throws {
        try await definitions.intents["CaptureBankMessageIntent"].makeIntent(message: nil).run()
    }

    func testCapturesAPayment() async throws {
        let intent = definitions.intents["CapturePaymentIntent"].makeIntent(
            amount: "45.000 ₫",
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
