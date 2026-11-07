import Foundation
import Testing
@testable import RiengtuKit

struct MoneyFormatStyleTests {
    static let english = Locale(identifier: "en_US")
    static let vietnamese = Locale(identifier: "vi_VN")

    /// Đồng with the sign after, in both languages.
    @Test func writesĐồngTheVietnameseWay() {
        let english = MoneyFormatStyle(currencyCode: "VND", locale: Self.english)
        let vietnamese = MoneyFormatStyle(currencyCode: "VND", locale: Self.vietnamese)
        #expect(english.format(45_000) == "45,000\u{00A0}₫")
        #expect(vietnamese.format(45_000) == "45.000\u{00A0}₫")
        #expect(english.format(-1_250_000) == "-1,250,000\u{00A0}₫")
        #expect(english.showingPlus().format(200_000) == "+200,000\u{00A0}₫")
        #expect(english.showingPlus().format(-200_000) == "-200,000\u{00A0}₫")
        // English in Vietnam groups digits as Vietnamese do.
        #expect(MoneyFormatStyle(currencyCode: "VND", locale: Locale(identifier: "en_VN")).format(45_000) == "45.000\u{00A0}₫")
    }

    @Test func writesOtherCurrenciesAsTheLocaleDoes() {
        let dollars = MoneyFormatStyle(currencyCode: "USD", locale: Locale(identifier: "en_US"))
        #expect(dollars.format(Decimal(string: "4.5")!) == "$4.50")
        #expect(dollars.showingPlus().format(20) == "+$20.00")
    }
}
