import Foundation

/// The currencies someone can record an expense in.
public enum Currencies {
    /// The ISO 4217 codes of the currencies countries and regions use today, such as `VND`,
    /// `USD` and `EUR`, in alphabetical order. Old ones, such as `DEM`, aren't in it.
    public static let all: [String] = {
        let codes = Locale.Region.isoRegions.compactMap { region in
            Locale(identifier: "en_\(region.identifier)").currency?.identifier
        }
        return Set(codes).filter(isValidCode).sorted()
    }()

    /// The currency of the locale's region, such as `VND` for Vietnam, or `USD` if it has none.
    public static func code(for locale: Locale) -> String {
        if let code = locale.currency?.identifier, isValidCode(code) {
            return code
        }
        return "USD"
    }

    /// How many digits the currency has after the decimal separator: 0 for `VND` and `JPY`, 2 for
    /// `USD`.
    public static func fractionDigits(for code: String) -> Int {
        currencyFormatter(code: code, locale: Locale(identifier: "en_US_POSIX")).maximumFractionDigits
    }

    /// The currency's symbol as the locale writes it, such as `₫` for `VND`, or `US$` for `USD`
    /// in Vietnamese.
    public static func symbol(for code: String, locale: Locale) -> String {
        currencyFormatter(code: code, locale: locale).currencySymbol
    }

    private static func isValidCode(_ code: String) -> Bool {
        // XXX is ISO 4217's "no currency".
        code.count == 3 && code.allSatisfy(\.isUppercase) && code != "XXX"
    }

    private static func currencyFormatter(code: String, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter
    }
}
