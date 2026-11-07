import Foundation
import Testing
@testable import RiengtuKit

/// Banks send ads, offers, one-time codes and reminders as they send transactions, and a
/// shortcut forwards them all. Made-up ones in the shapes banks use, with real ones as they turn
/// up, with account numbers and names changed.
struct NotTransactionTests {
    struct Sample: CustomTestStringConvertible, Sendable {
        var text: String
        var isTransaction: Bool

        var testDescription: String { String(text.prefix(40)) }
    }

    /// Techcombank's, as forwarded: title, then body. No digits.
    static let linkCardAd = Sample(text: """
        Liên kết thẻ, tiện mọi lần chi tiêu
        Liên kết thẻ tín dụng Techcombank với Apple Pay để thanh toán "một chạm" với Iphone/Apple Watch mọi nơi mà không cần mang theo thẻ hay ví. Liên kết ngay!
        """, isTransaction: false)

    /// Ones whose words say what they are, without Apple Intelligence too.
    static let worded: [Sample] = [
        Sample(text: """
            Hoàn tiền đến 50.000đ khi thanh toán bằng thẻ Visa tại Shopee, từ 01/11 đến 30/11/2026. Chi tiết tại https://example.com/uu-dai
            """, isTransaction: false),
        Sample(text: """
            Giảm 20% tối đa 100.000 VND cho đơn từ 200.000 VND khi thanh toán qua VNPAY-QR. Áp dụng đến hết 30/11.
            """, isTransaction: false),
        Sample(text: """
            Ma OTP cua Quy khach la 482913 de xac nhan giao dich 1.500.000 VND tai SHOPEE. Tuyet doi khong chia se ma nay cho bat ky ai.
            """, isTransaction: false),
        Sample(text: """
            Sao ke the tin dung ky 10/2026 cua Quy khach: du no 5,230,000 VND. Han thanh toan: 15/11/2026.
            """, isTransaction: false),
    ]

    /// Transactions with no sign or balance, which the rules can't tell plainly. Not one with
    /// words of an offer in what the sender wrote.
    static let unsigned: [Sample] = [
        Sample(text: "TK 1234567890 GD 50,000 VND tai GRAB 06/11/2026 10:20", isTransaction: true),
        Sample(text: "Quy khach da thanh toan 120.000 VND tai HIGHLANDS COFFEE luc 10:20 06/11/2026", isTransaction: true),
        Sample(text: """
            Số tiền: 500,000 VND
            Nội dung: MUNG SINH NHAT UU DAI
            """, isTransaction: true),
        Sample(text: """
            Tai khoan 1234567890 nhan 2,000,000 VND tu NGUYEN VAN AN luc 08:15 06/11/2026. ND: tra tien nha
            """, isTransaction: true),
    ]

    /// Ones only Apple Intelligence can tell: an offer without the words the rules know.
    static let unworded: [Sample] = [
        Sample(text: """
            Nhận ngay 50.000 VND khi mời bạn bè cài ứng dụng ngân hàng trước 30/11/2026. Mời ngay hôm nay!
            """, isTransaction: false),
    ]

    @Test func adWithoutDigits() {
        #expect(TransactionText.isTransaction(Self.linkCardAd.text) == false)
    }

    /// A + or − before the amount, or a balance, which ads and codes don't give.
    @MainActor @Test func plainTransactions() {
        #expect(TransactionText.isTransaction(InboxTests.notification) == true)
        #expect(TransactionText.isTransaction(InboxTests.transfer) == true)
        // Words of an offer, but a balance.
        #expect(TransactionText.isTransaction("""
            Số tiền GD: 50,000 VND
            Số dư: 1,000,000 VND
            Ưu đãi hoàn tiền tới 5% khi thanh toán bằng thẻ
            """) == true)
    }

    /// Left for Apple Intelligence.
    @Test(arguments: worded + unsigned + unworded)
    func notPlain(sample: Sample) {
        #expect(TransactionText.isTransaction(sample.text) == nil)
    }

    /// Without Apple Intelligence, the words tell.
    @Test(arguments: worded + unsigned)
    func words(sample: Sample) {
        #expect(TransactionText.looksLikeOtherMessage(sample.text) == !sample.isTransaction)
    }
}

/// Apple Intelligence tells an ad, a code or a reminder from a transaction, where the rules
/// can't plainly.
@Suite(.enabled(if: ExpenseTagger.availability == .available, "Needs Apple Intelligence"))
struct NotTransactionModelTests {
    @Test(arguments: NotTransactionTests.worded + NotTransactionTests.unsigned + NotTransactionTests.unworded)
    func tellsWhetherItsATransaction(sample: NotTransactionTests.Sample) async throws {
        let isTransaction = try await TransactionReader.isTransaction(sample.text)
        #expect(isTransaction == sample.isTransaction)
    }
}
