import Foundation
import Testing
@testable import RiengtuKit

/// Made-up receipts in the shapes shops print, as Vision reads them: a row for each line, its
/// pieces left to right.
struct ReceiptTextTests {
    static func rows(_ text: String) -> [ReceiptText.Row] {
        text.split(separator: "\n").map { ReceiptText.Row(cells: $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }) }
    }

    /// A café's bill, with a table of items, a discount and VAT.
    static let cafe = rows("""
        HIGHLANDS COFFEE
        Địa chỉ: 12 Nguyễn Huệ, Q.1, TP.HCM
        ĐT: 0281234567
        HÓA ĐƠN THANH TOÁN
        Số HĐ: 00012345 | Bàn: 05
        Ngày: 06/11/2026 12:30
        Tên món | SL | Đơn giá | Thành tiền
        Phin Sữa Đá | 2 | 29.000 | 58.000
        Bánh Mì Thịt | 1 | 35.000 | 35.000
        Trà Sen Vàng | 1 | 45.000 | 45.000
        Tổng tiền hàng | 138.000
        Giảm giá | 13.800
        VAT 8% | 9.936
        Tổng thanh toán | 134.136
        Tiền khách đưa | 200.000
        Tiền thừa | 65.864
        Cảm ơn quý khách!
        """)

    /// A supermarket's, with each item's quantity and price on the row below its name.
    static let supermarket = rows("""
        CO.OPMART NGUYEN DINH CHIEU
        168 Nguyễn Đình Chiểu, P.6, Q.3
        Sữa tươi Vinamilk 1L
        2 x 32.500 | 65.000
        Bánh quy Cosy
        1 x 25.000 | 25.000
        TỔNG CỘNG | 90.000
        TIỀN MẶT | 100.000
        TIỀN THỐI | 10.000
        """)

    /// One in dollars.
    static let dollars = rows("""
        Blue Bottle Coffee
        Latte | $5.25
        Croissant | $3.50
        Subtotal | $8.75
        Tax | $0.70
        Total | $9.45
        """)

    @Test func readsACafesBill() throws {
        let receipt = ReceiptText.receipt(from: Self.cafe, timeZone: TransactionTextTests.vietnam)
        #expect(receipt.merchant == "HIGHLANDS COFFEE")
        #expect(receipt.address == "12 Nguyễn Huệ, Q.1, TP.HCM")
        #expect(receipt.date == TransactionTextTests.date(6, 12, 30))
        #expect(receipt.currencyCode == "VND")
        #expect(receipt.items == [
            Receipt.Item(name: "Phin Sữa Đá", quantity: 2, unitPrice: 29_000, amount: 58_000),
            Receipt.Item(name: "Bánh Mì Thịt", quantity: 1, unitPrice: 35_000, amount: 35_000),
            Receipt.Item(name: "Trà Sen Vàng", quantity: 1, unitPrice: 45_000, amount: 45_000),
        ])
        #expect(receipt.subtotal == 138_000)
        #expect(receipt.discount == 13_800)
        #expect(receipt.tax == 9_936)
        // Not what was handed over, or the change.
        #expect(receipt.total == 134_136)
        #expect(receipt.reference == "00012345")
    }

    @Test func readsItemsOnTwoRows() {
        let receipt = ReceiptText.receipt(from: Self.supermarket)
        #expect(receipt.merchant == "CO.OPMART NGUYEN DINH CHIEU")
        #expect(receipt.address == "168 Nguyễn Đình Chiểu, P.6, Q.3")
        #expect(receipt.items == [
            Receipt.Item(name: "Sữa tươi Vinamilk 1L", quantity: 2, unitPrice: 32_500, amount: 65_000),
            Receipt.Item(name: "Bánh quy Cosy", quantity: 1, unitPrice: 25_000, amount: 25_000),
        ])
        #expect(receipt.total == 90_000)
        #expect(receipt.paymentMethod == "TIỀN MẶT")
    }

    @Test func readsDollars() {
        let receipt = ReceiptText.receipt(from: Self.dollars)
        #expect(receipt.currencyCode == "USD")
        #expect(receipt.merchant == "Blue Bottle Coffee")
        #expect(receipt.items.map(\.amount) == [Decimal(string: "5.25"), Decimal(string: "3.5")])
        #expect(receipt.subtotal == Decimal(string: "8.75"))
        #expect(receipt.tax == Decimal(string: "0.7"))
        #expect(receipt.total == Decimal(string: "9.45"))
    }

    /// Lines Vision found at about the same height are one row, left to right.
    @Test func putsLinesInRows() {
        let rows = ReceiptText.rows(from: [
            ScreenshotText.Line(text: "58.000", minX: 0.8, minY: 0.495, maxY: 0.515),
            ScreenshotText.Line(text: "Phin Sữa Đá", minX: 0.1, minY: 0.5, maxY: 0.52),
            ScreenshotText.Line(text: "HIGHLANDS COFFEE", minX: 0.3, minY: 0.1, maxY: 0.13),
        ])
        #expect(rows == [ReceiptText.Row(cells: ["HIGHLANDS COFFEE"]), ReceiptText.Row(cells: ["Phin Sữa Đá", "58.000"])])
    }

    @Test(arguments: [("58.000", 58_000), ("58,000", 58_000), ("58000", 58_000), ("58.000đ", 58_000), ("29K", 29_000), ("100.000₫", 100_000)])
    func readsAPrice(token: String, value: Decimal) {
        #expect(ReceiptText.price(Substring(token), fractionDigits: 0) == value)
    }

    @Test(arguments: ["0281234567", "00012345", "12:30", "06/11/2026", "05"])
    func readsNoPrice(token: String) {
        #expect(ReceiptText.price(Substring(token), fractionDigits: 0) == nil)
    }
}

/// What the model reads is checked against the receipt's text.
struct ReceiptCheckTests {
    static let text = ReceiptTextTests.cafe.map(\.text).joined(separator: "\n")

    @Test func leavesOutWhatTheReceiptDoesntSay() {
        let rules = ReceiptText.receipt(from: ReceiptTextTests.cafe, timeZone: TransactionTextTests.vietnam)
        let read = ReceiptReader.Read(
            merchant: "Highlands Coffee",
            items: [
                .init(name: "Phin Sữa Đá", quantity: "2", unitPrice: "29000", amount: "58000"),
                // Made up.
                .init(name: "Cà phê trứng", quantity: "1", amount: "40000"),
                // A price the receipt doesn't print.
                .init(name: "Bánh Mì Thịt", quantity: "1", amount: "36000"),
            ],
            // The cash handed over, not what was paid.
            total: "200000", currency: "VND"
        )
        let receipt = ReceiptReader.checked(read, against: rules, text: Self.text, timeZone: TransactionTextTests.vietnam)
        #expect(receipt.merchant == "Highlands Coffee")
        #expect(receipt.items.map(\.name) == ["Phin Sữa Đá", "Bánh Mì Thịt"])
        #expect(receipt.items.map(\.amount) == [58_000, nil])
        #expect(receipt.total == 134_136)
    }

    @Test func takesTheRulesWhereTheModelReadNothing() {
        let rules = ReceiptText.receipt(from: ReceiptTextTests.cafe, timeZone: TransactionTextTests.vietnam)
        let receipt = ReceiptReader.checked(
            ReceiptReader.Read(merchant: "", items: []), against: rules, text: Self.text, timeZone: TransactionTextTests.vietnam
        )
        #expect(receipt == rules)
    }
}

/// Apple Intelligence reads the sample receipts, on a Mac with it turned on.
@Suite(.enabled(if: ExpenseTagger.availability == .available, "Needs Apple Intelligence"))
struct ReceiptReaderTests {
    @Test func readsACafesBill() async {
        let receipt = await ReceiptReader.read(ReceiptTextTests.cafe, timeZone: TransactionTextTests.vietnam)
        print("RECEIPT", receipt)
        #expect(TransactionText.fold(receipt.merchant) == "highlands coffee")
        #expect(receipt.items.count == 3)
        #expect(receipt.items.compactMap(\.amount) == [58_000, 35_000, 45_000])
        #expect(receipt.total == 134_136)
    }

    @Test func readsItemsOnTwoRows() async {
        let receipt = await ReceiptReader.read(ReceiptTextTests.supermarket)
        print("RECEIPT", receipt)
        #expect(receipt.items.count == 2)
        #expect(receipt.items.compactMap(\.amount) == [65_000, 25_000])
        #expect(receipt.total == 90_000)
    }

    @Test func readsDollars() async {
        let receipt = await ReceiptReader.read(ReceiptTextTests.dollars)
        print("RECEIPT", receipt)
        #expect(receipt.currencyCode == "USD")
        #expect(receipt.items.count == 2)
        #expect(receipt.total == Decimal(string: "9.45"))
    }
}
