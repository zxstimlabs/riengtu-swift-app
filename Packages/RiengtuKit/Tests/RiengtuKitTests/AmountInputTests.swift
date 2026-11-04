import Foundation
import Testing
@testable import RiengtuKit

struct AmountInputTests {
    static let vietnamese = Locale(identifier: "vi_VN")
    static let english = Locale(identifier: "en_US")

    @Test(arguments: [
        ("1250000", "1.250.000"),
        ("1.250.000", "1.250.000"),
        ("0001250", "1.250"),
        ("0", "0"),
        ("", ""),
        ("abc", ""),
        // The đồng has no fraction, so a decimal separator is dropped.
        ("50,5", "505"),
    ])
    func groupsĐồngInVietnamese(typed: String, shown: String) {
        #expect(AmountInput.normalize(typed, fractionDigits: 0, locale: Self.vietnamese) == shown)
    }

    @Test(arguments: [
        ("1234.5", "1,234.5"),
        ("1234.567", "1,234.56"),
        ("1,234", "1,234"),
        (".", "0."),
        ("12.", "12."),
        ("1.2.3", "1.23"),
    ])
    func keepsCentsInEnglish(typed: String, shown: String) {
        #expect(AmountInput.normalize(typed, fractionDigits: 2, locale: Self.english) == shown)
    }

    @Test func usesTheLocalesDecimalComma() {
        #expect(AmountInput.normalize("1234,5", fractionDigits: 2, locale: Self.vietnamese) == "1.234,5")
    }

    /// With the Vietnam region and an English keyboard, the decimal pad types `.` but the region
    /// writes `,`.
    @Test func readsTheDecimalKeyJustTypedWhateverItIs() {
        #expect(AmountInput.normalize("12.", fractionDigits: 2, locale: Self.vietnamese) == "12,")
        #expect(AmountInput.normalize("1.234.", fractionDigits: 2, locale: Self.vietnamese) == "1.234,")
        #expect(AmountInput.normalize("12,", fractionDigits: 2, locale: Self.english) == "12.")
        // Before the end, only the locale's own decimal separator counts.
        #expect(AmountInput.normalize("1.234", fractionDigits: 2, locale: Self.vietnamese) == "1.234")
        // Typing on after the decimal key, once it's been tidied.
        let tidied = AmountInput.normalize("12.", fractionDigits: 2, locale: Self.vietnamese)
        #expect(AmountInput.normalize(tidied + "5", fractionDigits: 2, locale: Self.vietnamese) == "12,5")
        #expect(AmountInput.parse("12,5", locale: Self.vietnamese) == Decimal(string: "12.5"))
        // The đồng has no fraction, so the key is ignored.
        #expect(AmountInput.normalize("1.234.", fractionDigits: 0, locale: Self.vietnamese) == "1.234")
    }

    @Test func capsTheWholePart() {
        let typed = String(repeating: "9", count: 20)
        let digits = AmountInput.normalize(typed, fractionDigits: 0, locale: Self.english).filter(\.isNumber)
        #expect(digits.count == AmountInput.maxWholeDigits)
    }

    @Test(arguments: [
        ("1.250.000", Locale(identifier: "vi_VN"), Decimal(1_250_000)),
        ("1.234,5", Locale(identifier: "vi_VN"), Decimal(string: "1234.5")!),
        ("1,234.5", Locale(identifier: "en_US"), Decimal(string: "1234.5")!),
        ("0.", Locale(identifier: "en_US"), Decimal(0)),
    ])
    func parses(text: String, locale: Locale, amount: Decimal) {
        #expect(AmountInput.parse(text, locale: locale) == amount)
    }

    @Test(arguments: ["", ".", "abc"])
    func parsesNothingWithoutDigits(text: String) {
        #expect(AmountInput.parse(text, locale: Self.english) == nil)
    }

    @Test func showsAnAmountForEditing() {
        #expect(AmountInput.text(for: 1_250_000, fractionDigits: 0, locale: Self.vietnamese) == "1.250.000")
        #expect(AmountInput.text(for: Decimal(string: "1234.5")!, fractionDigits: 2, locale: Self.english) == "1,234.5")
        #expect(AmountInput.text(for: Decimal(string: "1234.5")!, fractionDigits: 2, locale: Self.vietnamese) == "1.234,5")
        // Rounded when the new currency has fewer fraction digits.
        #expect(AmountInput.text(for: Decimal(string: "12.6")!, fractionDigits: 0, locale: Self.english) == "13")
    }
}

struct CurrenciesTests {
    @Test func listsCurrenciesInUse() {
        let all = Set(Currencies.all)
        #expect(all.isSuperset(of: ["VND", "USD", "EUR", "JPY", "XOF"]))
        #expect(!all.contains("DEM"))
        #expect(!all.contains("XXX"))
        #expect(Currencies.all == Currencies.all.sorted())
    }

    @Test(arguments: [("VND", 0), ("JPY", 0), ("USD", 2), ("EUR", 2), ("KWD", 3)])
    func knowsFractionDigits(code: String, digits: Int) {
        #expect(Currencies.fractionDigits(for: code) == digits)
    }

    @Test func picksTheRegionsCurrency() {
        #expect(Currencies.code(for: Locale(identifier: "vi_VN")) == "VND")
        #expect(Currencies.code(for: Locale(identifier: "en_US")) == "USD")
        #expect(Currencies.code(for: Locale(identifier: "en")) == "USD")
    }

    @Test func writesTheSymbol() {
        #expect(Currencies.symbol(for: "VND", locale: Locale(identifier: "vi_VN")) == "₫")
        #expect(Currencies.symbol(for: "USD", locale: Locale(identifier: "en_US")) == "$")
    }
}
