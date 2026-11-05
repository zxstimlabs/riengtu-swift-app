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

    @Test func foldsKeepingOneCharacterForEach() {
        let text = "Nội dung ĐÃ chuyển"
        #expect(TransactionText.fold(text) == "noi dung da chuyen")
        #expect(TransactionText.fold(text).count == text.count)
    }
}
