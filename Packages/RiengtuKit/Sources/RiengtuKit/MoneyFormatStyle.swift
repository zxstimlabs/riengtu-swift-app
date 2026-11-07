import Foundation

/// Formats an amount of money with its currency, as `.currency(code:)` does, except that đồng
/// are written the Vietnamese way in every language, with the sign after the number: "45.000 ₫"
/// in Vietnamese and "45,000 ₫" in English, where `.currency` writes "₫45,000". The digits are
/// grouped as the locale groups them.
public struct MoneyFormatStyle: FormatStyle, Sendable {
    public var currencyCode: String
    public var locale: Locale
    /// Whether amounts above zero get a plus.
    public var showsPlus = false

    public init(currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    public func format(_ value: Decimal) -> String {
        let sign: NumberFormatStyleConfiguration.SignDisplayStrategy = showsPlus ? .always() : .automatic
        guard Currencies.writesSymbolAfter(currencyCode) else {
            return Decimal.FormatStyle.Currency(code: currencyCode, locale: locale).sign(strategy: currencySign).format(value)
        }
        let number = Decimal.FormatStyle(locale: locale)
            .precision(.fractionLength(0...Currencies.fractionDigits(for: currencyCode)))
            .sign(strategy: sign)
            .format(value)
        // A space that doesn't break, so the sign stays with the number.
        return number + "\u{00A0}" + Currencies.symbol(for: currencyCode, locale: Locale(identifier: "vi_VN"))
    }

    private var currencySign: CurrencyFormatStyleConfiguration.SignDisplayStrategy {
        showsPlus ? .always() : .automatic
    }

    public func locale(_ locale: Locale) -> MoneyFormatStyle {
        var style = self
        style.locale = locale
        return style
    }

    /// With a plus for amounts above zero, as for money that came in.
    public func showingPlus() -> MoneyFormatStyle {
        var style = self
        style.showsPlus = true
        return style
    }
}

extension FormatStyle where Self == MoneyFormatStyle {
    /// An amount in `code`, with đồng written the Vietnamese way (`MoneyFormatStyle`).
    public static func money(code: String) -> MoneyFormatStyle {
        MoneyFormatStyle(currencyCode: code)
    }
}
