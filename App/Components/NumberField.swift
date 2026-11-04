import RiengtuKit
import SwiftUI

/// A text field for an amount, a price or a quantity, tidied as it's typed: the digits grouped in
/// the device's number format, and no more fraction digits than `fractionDigits`.
///
/// When `fractionDigits` changes, such as with the currency, the number is kept and rounded.
struct NumberField: View {
    /// What VoiceOver reads. The field shows a 0 until something is typed.
    let title: Text
    @Binding var text: String
    let fractionDigits: Int

    /// Numbers are typed in the device's number format, which is what the keyboard's decimal key
    /// follows, whatever the app's language.
    static let locale = Locale.autoupdatingCurrent

    /// The number in `text`, or `nil` if it has no digits.
    static func number(in text: String) -> Decimal? {
        AmountInput.parse(text, locale: locale)
    }

    /// The text that shows `number` in a field with `fractionDigits`.
    static func text(for number: Decimal, fractionDigits: Int) -> String {
        AmountInput.text(for: number, fractionDigits: fractionDigits, locale: locale)
    }

    var body: some View {
        TextField(text: $text, prompt: Text(verbatim: "0")) { title }
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .onChange(of: text) { _, typed in
                let normalized = AmountInput.normalize(typed, fractionDigits: fractionDigits, locale: Self.locale)
                if normalized != typed { text = normalized }
            }
            .onChange(of: fractionDigits) {
                if let number = Self.number(in: text) {
                    text = Self.text(for: number, fractionDigits: fractionDigits)
                }
            }
    }
}
