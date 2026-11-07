import Foundation
import Testing
@testable import RiengtuKit

/// Made-up notices in the shapes Vietnamese banks use. Real ones can be added as they turn up,
/// with account numbers and names changed.
struct TransactionTextTests {
    static let vietnam = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    static func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = vietnam
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
    }

    static func read(_ text: String) -> TransactionText.Reading {
        TransactionText.read(text, timeZone: vietnam)
    }

    @Test func readsAVietnameseTransferEmail() {
        let reading = Self.read("""
            Kính gửi Quý khách,
            Ngân hàng xin thông báo tài khoản 0011004123456 của Quý khách vừa thay đổi:
            Số tiền giao dịch: -150,000 VND
            Số dư hiện tại: 12,345,678 VND
            Thời gian: 05/11/2026 12:30:01
            Nội dung giao dịch: CHUYEN TIEN AN TRUA
            Trân trọng.
            """)
        #expect(reading == TransactionText.Reading(
            amount: 150_000, currencyCode: "VND", direction: .moneyOut,
            date: Self.date(5, 12, 30, 1), description: "CHUYEN TIEN AN TRUA"
        ))
    }

    @Test func readsAnEnglishEmailWithTheCurrencyFirst() {
        let reading = Self.read("""
            Dear Customer,
            Your account 19031234567 has been debited.
            Balance: VND 20,000,000
            Amount: VND 1,250,000
            Time: 12:45 05/11/2026
            Description: QR payment to HIGHLANDS COFFEE
            """)
        #expect(reading.amount == 1_250_000)
        #expect(reading.currencyCode == "VND")
        #expect(reading.direction == .moneyOut)
        #expect(reading.date == Self.date(5, 12, 45))
        #expect(reading.description == "QR payment to HIGHLANDS COFFEE")
    }

    @Test func readsAOneLineMessage() {
        let reading = Self.read("TK 0123456789 -45,000VND luc 05-11-2026 08:15:00. SD 3,500,000VND. ND: PHO BO")
        #expect(reading.amount == 45_000)
        #expect(reading.direction == .moneyOut)
        #expect(reading.date == Self.date(5, 8, 15))
        #expect(reading.description == "PHO BO")
    }

    /// Techcombank's app notification: the amount and its sign are the title, and what it was for,
    /// without a label, follows the balance.
    @Test func readsATechcombankNotification() {
        let reading = Self.read("""
            - VND 25,000
            Tài khoản: 1234567890
            Số dư: VND 16,181,570
            NGUYEN VAN AN chuyen tien. Ma tham chieu 123456
            """)
        #expect(reading == TransactionText.Reading(
            amount: 25_000, currencyCode: "VND", direction: .moneyOut, description: "NGUYEN VAN AN chuyen tien"
        ))
    }

    @Test func readsATechcombankNotificationWithTheAmountAgain() {
        let reading = Self.read("""
            - VND 2,042,000
            Tài khoản: 1234567890
            Số dư: VND 16,206,570
            Thanh toan no the tin dung _ So tien 2042000 VND _ Ngay 05/11/2026
            """)
        #expect(reading == TransactionText.Reading(
            amount: 2_042_000, currencyCode: "VND", direction: .moneyOut,
            date: Self.date(5, 0, 0), description: "Thanh toan no the tin dung"
        ))
    }

    @Test func readsATechcombankNotificationOfMoneyIn() {
        let reading = Self.read("""
            + VND 5,000,000
            Tài khoản: 1234567890
            Số dư: VND 21,181,570
            CONG TY ABC tra luong thang 10
            """)
        #expect(reading.amount == 5_000_000)
        #expect(reading.direction == .moneyIn)
        #expect(reading.description == "CONG TY ABC tra luong thang 10")
    }

    /// Techcombank's history: amounts without their currency, after a label.
    @Test func readsAnAmountWithoutItsCurrencyAfterALabel() {
        let reading = Self.read("""
            Tài khoản 1234567890
            Số tiền GD: - 1,504,246
            Số dư: 18,475,880
            Thanh toan dich vu Dien cho CONG TY DIEN LUC SAI GON cho Ma HD PE02000125105 - 1504246 VND - 03/11/2026 06:19:40
            """)
        #expect(reading.amount == 1_504_246)
        #expect(reading.currencyCode == "VND")
        #expect(reading.direction == .moneyOut)
        #expect(reading.date == Self.date(3, 6, 19, 40))
        #expect(TransactionText.amounts(in: "Số tiền GD: + 10,000\nSố dư: 18,263,570").map(\.isBalance) == [false, true])
    }

    /// A credit card's available limit isn't what moved.
    @Test func readsACardPaymentOverItsLimit() {
        let reading = Self.read("""
            Thẻ: 4 .... .... 1234
            Số tiền: - VND 90,000
            Hạn mức khả dụng tạm tính: VND 66,766,000
            Thanh toán tại .OP*Green SM
            """)
        #expect(reading.amount == 90_000)
        #expect(reading.direction == .moneyOut)
        #expect(reading.description == "Thanh toán tại .OP*Green SM")
        #expect(TransactionText.amounts(in: "Hạn mức khả dụng tạm tính: VND 66,766,000").first?.isBalance == true)
    }

    /// ACB's message: the currency in brackets, then the sign and the amount.
    @Test func readsAnACBMessage() {
        let reading = Self.read("""
            Thong bao thay doi so du tai khoan
            ACB: TK 123456789(VND) - 100,000 luc 00:31 07/11/2026. So du 69,272,331. GD: NGUYEN VAN AN CHUYEN KHOAN-071126-00:31:28 6311ASCB02V2Q9YC
            """)
        #expect(reading.amount == 100_000)
        #expect(reading.currencyCode == "VND")
        #expect(reading.direction == .moneyOut)
        #expect(reading.date == Self.date(7, 0, 31))
        #expect(reading.description == "NGUYEN VAN AN CHUYEN KHOAN")
        #expect(TransactionText.statedDirection(in: "ACB: TK 123456789(VND) + 5,000,000 luc 08:00 07/11/2026") == .moneyIn)
        #expect(TransactionText.amounts(in: "So du 69,272,331").first?.isBalance == true)
    }

    /// What the model reads: the words as they came, the rest as tokens.
    @Test func tokensANoticeForTheModel() {
        let notice = TransactionText.notice(for: """
            Thong bao thay doi so du tai khoan
            ACB: TK 123456789(VND) - 100,000 luc 00:31 07/11/2026. So du 69,272,331. GD: NGUYEN VAN AN CHUYEN KHOAN-071126-00:31:28 6311ASCB02V2Q9YC
            """)
        #expect(notice.prompt == """
            Thong bao thay doi so du tai khoan
            ACB: TK [account]([money out 100000 VND] luc [time]. So du [balance]. GD: NGUYEN VAN AN CHUYEN KHOAN-[account]-[time] [code]
            """)
        #expect(notice.amount == 100_000)
        #expect(notice.direction == .moneyOut)
        #expect(TransactionText.notice(for: "Thẻ: 4 .... .... 1234\nSố tiền: - VND 90,000\nHạn mức khả dụng tạm tính: VND 66,766,000\nThanh toán tại .OP*Green SM\n22:00").prompt
            == "Thẻ: [card]\nSố tiền: [money out 90000 VND]\nHạn mức khả dụng tạm tính: [balance]\nThanh toán tại .OP*Green SM\n[time]")
    }

    @Test(arguments: [
        "Số tiền: –500,000 VND", "Số tiền: — 500,000 VND", "Số tiền: －500,000 VND", "Số tiền:\t-\t500,000 VND",
        "Số tiền: -          500,000 VND", "- VND 500,000",
    ])
    func readsAMinusHoweverItsWritten(text: String) {
        #expect(TransactionText.statedDirection(in: text) == .moneyOut)
        #expect(Self.read(text).amount == 500_000)
    }

    /// MB writes the amount after "GD:", which isn't what it was for.
    @Test func leavesOutAnAmountAfterALabel() {
        #expect(Self.read("TK 1234567890|GD: -500,000VND 07/11/26 08:00|SD: 1,000,000VND").description.isEmpty)
    }

    @Test func tellsMoneyIn() {
        let reading = Self.read("TK 0123456789 +5.000.000 VND luc 05/11/2026 09:00. SD 8.500.000 VND. ND: Luong thang 10")
        #expect(reading.amount == 5_000_000)
        #expect(reading.direction == .moneyIn)
        #expect(Self.read("Tài khoản của bạn vừa được ghi có 200,000đ").direction == .moneyIn)
        #expect(Self.read("Số dư tài khoản vừa tăng 200.000 VND").direction == .moneyIn)
    }

    @Test func prefersTheTransactionToTheBalance() {
        let reading = Self.read("Số dư: 10.000.000đ. Giao dịch: 200.000đ")
        #expect(reading.amount == 200_000)
        #expect(reading.direction == nil)
    }

    @Test func readsWordsForMoneyOut() {
        let reading = Self.read("Thanh toán 150.000đ tại Circle K")
        #expect(reading.amount == 150_000)
        #expect(reading.direction == .moneyOut)
    }

    @Test func readsCents() {
        let reading = Self.read("Amount: USD 12.50 debited at STARBUCKS")
        #expect(reading.amount == Decimal(string: "12.5"))
        #expect(reading.currencyCode == "USD")
        #expect(reading.direction == .moneyOut)
        #expect(reading.description.isEmpty)
    }

    @Test func dropsTheZerosAfterAnAmountInĐồng() {
        #expect(Self.read("Số tiền: -150,000.00 VND").amount == 150_000)
    }

    @Test func ignoresDigitsThatArentAnAmount() {
        // The account number runs into the amount's digits, and the hotline has no currency.
        let reading = Self.read("Hotline 1900 545413. Tài khoản 0011004123456 vừa giảm 99.000 VND")
        #expect(reading.amount == 99_000)
        #expect(reading.direction == .moneyOut)
        #expect(Self.read("Chào mừng Quý khách đến với ngân hàng. Hotline 1900 545413").amount == nil)
    }

    @Test func readsDescriptionsAfterOtherLabels() {
        #expect(Self.read("Merchant: GRAB*TRIP 12345\n-60,000 VND").description == "GRAB*TRIP 12345")
        #expect(Self.read("Người nhận: NGUYEN VAN A\nSố tiền: -500,000 VND").description == "NGUYEN VAN A")
        // "Nội dung" wins over "Người nhận".
        #expect(Self.read("Người nhận: NGUYEN VAN A\nNội dung: Tien nha\n-500,000 VND").description == "Tien nha")
    }

    @Test(arguments: [
        ("MBVCB.11223344.556677.NGUYEN VAN A chuyen tien an trua.CT tu 0011004123456 NGUYEN VAN A toi 1903123 CONG TY ABC", "NGUYEN VAN A chuyen tien an trua"),
        ("TT QR VNPAY 987654321 HIGHLANDS COFFEE", "TT QR VNPAY HIGHLANDS COFFEE"),
        ("0901234567-Chuyen tien hoc phi cho con", "Chuyen tien hoc phi cho con"),
        ("hóa đơn tiền điện kỳ 10/2026", "hóa đơn tiền điện kỳ 10/2026"),
        ("Tien nha thang 11", "Tien nha thang 11"),
    ])
    func cleansWhatBanksAddAroundADescription(raw: String, cleaned: String) {
        #expect(TransactionText.clean(raw) == cleaned)
    }

    @Test func keepsDescriptionsShort() {
        let long = String(repeating: "A", count: 300)
        #expect(Self.read("ND: \(long)").description.count == TransactionText.descriptionMaximumLength)
    }

    @Test(arguments: [
        ("150,000", 0, Decimal(150_000)),
        ("150.000", 0, Decimal(150_000)),
        ("1 250 000", 0, Decimal(1_250_000)),
        ("150,000.00", 0, Decimal(150_000)),
        ("12.50", 2, Decimal(string: "12.5")!),
        ("1,234.56", 2, Decimal(string: "1234.56")!),
        ("1.234,56", 2, Decimal(string: "1234.56")!),
    ])
    func parsesNumbers(text: String, fractionDigits: Int, value: Decimal) {
        #expect(TransactionText.parseNumber(text, fractionDigits: fractionDigits) == value)
    }

    /// The ways Wallet may write a payment's amount, in Vietnamese, English and other formats.
    @Test(arguments: [
        ("45.000 ₫", Decimal(45_000), "VND"),
        ("₫45,000", Decimal(45_000), "VND"),
        ("45.000\u{00A0}₫", Decimal(45_000), "VND"),
        ("-45.000 ₫", Decimal(45_000), "VND"),
        ("VND 1,250,000", Decimal(1_250_000), "VND"),
        ("45.000,00 ₫", Decimal(45_000), "VND"),
        ("$12.50", Decimal(string: "12.5")!, "USD"),
        ("US$12.50", Decimal(string: "12.5")!, "USD"),
        ("12,50 €", Decimal(string: "12.5")!, "EUR"),
        ("1\u{202F}234,56 €", Decimal(string: "1234.56")!, "EUR"),
        ("CA$12.50", Decimal(string: "12.5")!, "CAD"),
        ("฿350.00", Decimal(350), "THB"),
        ("£8.20", Decimal(string: "8.2")!, "GBP"),
        ("THB 350.00", Decimal(350), "THB"),
        ("¥1,200", Decimal(1_200), "JPY"),
    ] as [(String, Decimal, String)])
    func readsAnAmountOnItsOwn(text: String, value: Decimal, currencyCode: String) throws {
        let amount = try #require(TransactionText.amount(text))
        #expect(amount.value == value)
        #expect(amount.currencyCode == currencyCode)
    }

    @Test func readsAnAmountWithoutItsCurrency() throws {
        let amount = try #require(TransactionText.amount("45000"))
        #expect(amount.value == 45_000)
        #expect(amount.currencyCode == nil)
        #expect(TransactionText.amount("45.000")?.value == 45_000)
        #expect(TransactionText.amount("12.50")?.value == Decimal(string: "12.5"))
    }

    @Test(arguments: ["", "₫", "Pending", "all"])
    func readsNoAmountWithoutANumber(text: String) {
        #expect(TransactionText.amount(text) == nil)
    }

    @Test(arguments: [
        ("Thanh toan dich vu Dien cho CONG TY DIEN LUC SAI GON cho Ma HD PE02000123456 - 1504246 VND - 03/11/2026 06:19:40",
         "Thanh toan dich vu Dien cho CONG TY DIEN LUC SAI GON"),
        ("NGUYEN VAN AN CHUYEN KHOAN-05112 6-14:26:22 6309ASCB02KNR93T", "NGUYEN VAN AN CHUYEN KHOAN"),
    ])
    func cutsTheCodesAfterADescription(raw: String, cleaned: String) {
        #expect(TransactionText.clean(raw) == cleaned)
    }

    @Test(arguments: [
        ("NGUYEN VAN AN chuyen tien", true),
        ("TRAN THI BINH CHUYEN KHOAN", true),
        ("CHUYEN TIEN AN TRUA", false),
        ("NGUYEN VAN AN chuyen tien an trua", false),
        ("Highlands Coffee", false),
    ])
    func tellsTheBanksDefaultTransferContent(description: String, isDefault: Bool) {
        #expect(TransactionText.isDefaultTransferContent(description) == isDefault)
    }

    @Test func foldsKeepingOneCharacterForEach() {
        let text = "Nội dung ĐÃ chuyển"
        #expect(TransactionText.fold(text) == "noi dung da chuyen")
        #expect(TransactionText.fold(text).count == text.count)
    }
}
