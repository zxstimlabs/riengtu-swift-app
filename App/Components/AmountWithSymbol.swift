import RiengtuKit
import SwiftUI

/// A field for an amount with its currency's symbol: after the number for đồng, as Vietnamese
/// write it ("45.000 ₫"), and before it for other currencies, as their formats do ("$4.50"). With
/// the symbol after, the field is only as wide as its number, so the symbol follows it.
struct AmountWithSymbol<Field: View>: View {
    let code: String
    var spacing: CGFloat = 8
    /// Whether to show a red minus before the number, for a balance below zero.
    var isBelowZero = false
    @ViewBuilder let field: Field

    var body: some View {
        let symbol = Text(verbatim: Currencies.symbol(for: code, locale: Currencies.writesSymbolAfter(code) ? Locale(identifier: "vi_VN") : NumberField.locale))
            .foregroundStyle(isBelowZero ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            if isBelowZero {
                Text(verbatim: "−")
                    .foregroundStyle(.red)
            }
            if Currencies.writesSymbolAfter(code) {
                field
                    .fixedSize(horizontal: true, vertical: false)
                symbol
            } else {
                symbol
                field
            }
        }
    }
}
