import Foundation

/// The text in an amount field, as someone types it in their locale.
///
/// Amounts are grouped as they're typed, so `1250000` reads `1.250.000` in Vietnamese and
/// `1,250,000` in English. That matters for currencies such as the đồng, where everyday amounts
/// run to seven digits.
public enum AmountInput {
    /// Whole parts longer than this are cut, which still allows hundreds of trillions.
    static let maxWholeDigits = 15

    /// Tidies what was typed: keeps the digits and the first decimal separator, groups the whole
    /// part, and drops fraction digits past what the currency has.
    ///
    /// Grouping separators and anything else are ignored, wherever they are. With
    /// `fractionDigits` 0, so is the decimal separator.
    ///
    /// A `.` or `,` at the very end is read as the decimal separator, whatever the locale's is.
    /// That's the key just typed, and the decimal pad's key can differ from the separator the
    /// region writes: with the Vietnam region, it types `.` where amounts show `,`, such as when
    /// the 1,234.56 Number Format is chosen in Settings. The field groups digits itself, so no one
    /// needs to type a grouping separator.
    public static func normalize(_ text: String, fractionDigits: Int, locale: Locale) -> String {
        let parts = Parts(text, fractionDigits: fractionDigits, locale: locale)
        guard parts.hasDigits || parts.fraction != nil else { return "" }

        let whole = Int(parts.whole).map { $0.formatted(.number.locale(locale)) } ?? "0"
        guard let fraction = parts.fraction else { return whole }
        return whole + decimalSeparator(locale) + fraction
    }

    /// The amount in `text`, or `nil` if it has no digits.
    public static func parse(_ text: String, locale: Locale) -> Decimal? {
        let parts = Parts(text, fractionDigits: .max, locale: locale)
        guard parts.hasDigits else { return nil }
        let number = parts.whole.isEmpty ? "0" : parts.whole
        let fraction = parts.fraction.map { "." + $0 } ?? ""
        return Decimal(string: number + fraction, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The text that shows `amount` in the field, rounded to the currency's fraction digits.
    public static func text(for amount: Decimal, fractionDigits: Int, locale: Locale) -> String {
        var amount = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, fractionDigits, .plain)
        let typed = rounded.description.replacingOccurrences(of: ".", with: decimalSeparator(locale))
        return normalize(typed, fractionDigits: fractionDigits, locale: locale)
    }

    /// The decimal separator as `FormatStyle` writes it, which is also what groups the digits here
    /// and formats amounts everywhere else in the app.
    ///
    /// Not `locale.decimalSeparator`: that follows a number format the person picked in Settings
    /// (Language & Region > Number Format), but `FormatStyle` keeps the region's. With the Vietnam
    /// region and the 1,234.56 format, the two disagree, and `1.250.000` would read as 1.25.
    static func decimalSeparator(_ locale: Locale) -> String {
        let oneAndAHalf = (Decimal(15) / 10).formatted(.number.locale(locale))
        return oneAndAHalf.first { !$0.isNumber }.map(String.init) ?? "."
    }

    /// The digits before and after the decimal separator.
    private struct Parts {
        /// Without leading zeros.
        var whole = ""
        /// `nil` without a decimal separator, empty right after one.
        var fraction: String?
        var hasDigits = false

        init(_ text: String, fractionDigits: Int, locale: Locale) {
            let separator = AmountInput.decimalSeparator(locale)
            for (index, character) in zip(text.indices, text) {
                let isLast = text.index(after: index) == text.endIndex
                if let digit = character.wholeNumberValue, character.isASCII {
                    hasDigits = true
                    if let current = fraction {
                        if current.count < fractionDigits { fraction = current + String(digit) }
                    } else if whole.count < AmountInput.maxWholeDigits, !(whole.isEmpty && digit == 0) {
                        whole += String(digit)
                    }
                } else if fraction == nil, fractionDigits > 0,
                          String(character) == separator || (isLast && (character == "." || character == ",")) {
                    fraction = ""
                }
            }
        }
    }
}
