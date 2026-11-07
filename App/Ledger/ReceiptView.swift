import RiengtuKit
import SwiftUI

/// A receipt as it was read, laid out as one, by the user's design: the shop at the top; each
/// item with its quantity and amount; the subtotal and discount; what was paid, large; then its
/// number, time and how it was paid; between dashed lines, on paper with torn edges. The paper
/// is light in dark mode too, as a receipt is.
struct ReceiptView: View {
    let receipt: Receipt

    @Environment(\.colorScheme) private var colorScheme

    private enum Part: Hashable {
        case shop, items, subtotals, total, details
    }

    private var parts: [Part] {
        var parts: [Part] = []
        if !receipt.merchant.isEmpty || !receipt.address.isEmpty { parts.append(.shop) }
        if !receipt.items.isEmpty { parts.append(.items) }
        if receipt.subtotal != nil || receipt.discount != nil || receipt.tax != nil { parts.append(.subtotals) }
        if receipt.total != nil { parts.append(.total) }
        if !receipt.reference.isEmpty || receipt.date != nil || !receipt.paymentMethod.isEmpty { parts.append(.details) }
        return parts
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.element) { index, part in
                if index > 0 {
                    DashedLine()
                }
                content(of: part)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .environment(\.colorScheme, .light)
        .background {
            // On the paper alone, not on each line of text.
            TornEdges()
                .fill(colorScheme == .dark ? Color(white: 0.95) : .white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.1), radius: 8, y: 2)
        }
    }

    @ViewBuilder private func content(of part: Part) -> some View {
        switch part {
        case .shop:
            VStack(spacing: 4) {
                if !receipt.merchant.isEmpty {
                    Text(verbatim: receipt.merchant)
                        .font(.title3.bold())
                }
                if !receipt.address.isEmpty {
                    Text(verbatim: receipt.address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        case .items:
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 18) {
                ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(verbatim: item.name)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: item.quantity?.formatted() ?? "")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.center)
                        money(item.amount)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .padding(.vertical, 20)
        case .subtotals:
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                if let subtotal = receipt.subtotal {
                    row(Text("Subtotal").foregroundStyle(.secondary), money(subtotal))
                }
                if let discount = receipt.discount {
                    row(Text("Discount"), money(-discount))
                }
                if let tax = receipt.tax {
                    row(Text("Tax").foregroundStyle(.secondary), money(tax))
                }
            }
            .font(.subheadline)
            .padding(.vertical, 18)
        case .total:
            VStack(spacing: 8) {
                Text("Total Paid")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let total = receipt.total {
                    Text(total, format: .money(code: receipt.currencyCode))
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        case .details:
            VStack(spacing: 10) {
                if !receipt.reference.isEmpty {
                    detail(Text("Reference"), Text(verbatim: receipt.reference))
                }
                if let date = receipt.date {
                    detail(Text("Time"), Text(date, format: .dateTime.hour().minute().day().month().year()))
                }
                if !receipt.paymentMethod.isEmpty {
                    detail(Text("Paid With"), Text(verbatim: receipt.paymentMethod))
                }
            }
            .font(.subheadline)
            .padding(.vertical, 18)
        }
    }

    private func row(_ label: some View, _ value: some View) -> some View {
        GridRow {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
            value
                .multilineTextAlignment(.trailing)
                .gridColumnAlignment(.trailing)
        }
    }

    /// A label, and its value on the right, which gets the room first: a code reads on one line.
    private func detail(_ label: Text, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            label
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            value
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }

    @ViewBuilder private func money(_ amount: Decimal?) -> some View {
        if let amount {
            Text(amount, format: .money(code: receipt.currencyCode))
        } else {
            Text(verbatim: "–")
                .foregroundStyle(.secondary)
        }
    }
}

/// The whole receipt, opened from its row in the editor.
struct ReceiptSheet: View {
    let receipt: Receipt

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ReceiptView(receipt: receipt)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
            }
            .background(backdrop)
            .navigationTitle("Receipt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .privacyShield()
    }

    private var backdrop: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color.gray.opacity(0.15)
        #endif
    }
}

/// A receipt in the editor, to tap for the whole of it: the shop, how many items, and the total.
struct ReceiptSummary: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbolName: "receipt", color: .gray)
            VStack(alignment: .leading, spacing: 2) {
                if receipt.merchant.isEmpty {
                    Text("Receipt")
                } else {
                    Text(verbatim: receipt.merchant)
                        .lineLimit(1)
                }
                if !receipt.items.isEmpty {
                    Text("\(receipt.items.count) items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let total = receipt.total {
                Text(total, format: .money(code: receipt.currencyCode))
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

/// A dashed line across a receipt.
private struct DashedLine: View {
    var body: some View {
        Line()
            .stroke(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    nonisolated private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// Paper torn along the top and the bottom, in small teeth.
nonisolated private struct TornEdges: Shape {
    var tooth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let count = max(1, Int((rect.width / (tooth * 2)).rounded()))
        let step = rect.width / CGFloat(count)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + tooth))
            for index in 0..<count {
                let x = rect.minX + CGFloat(index) * step
                path.addLine(to: CGPoint(x: x + step / 2, y: rect.minY))
                path.addLine(to: CGPoint(x: x + step, y: rect.minY + tooth))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
            for index in (0..<count).reversed() {
                let x = rect.minX + CGFloat(index) * step
                path.addLine(to: CGPoint(x: x + step / 2, y: rect.maxY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY - tooth))
            }
            path.closeSubpath()
        }
    }
}

extension Receipt {
    /// A sample, for previews.
    static let preview = Receipt(
        merchant: "LOCAL BRAND STORE", address: "12 Nguyễn Huệ, Q.1, TP.HCM", date: .now,
        items: [
            Receipt.Item(name: "Áo thun cotton basic", quantity: 2, unitPrice: 250_000, amount: 500_000),
            Receipt.Item(name: "Quần jogger nỉ bông", quantity: 1, unitPrice: 420_000, amount: 420_000),
            Receipt.Item(name: "Tất cổ ngắn (set 3 đôi)", quantity: 3, unitPrice: 60_000, amount: 180_000),
            Receipt.Item(name: "Combo đồng phục doanh nghiệp áo thun cổ bẻ thêu logo và quần kaki công sở", quantity: 1, amount: 1_850_000),
        ],
        subtotal: 2_950_000, discount: 50_000, total: 2_900_000, currencyCode: "VND",
        reference: "VQR-20260714-8842", paymentMethod: "VietQR"
    )
}

#Preview("Receipt") {
    ReceiptSheet(receipt: .preview)
        .previewEnvironment()
}

#Preview("Vietnamese, dark") {
    ReceiptSheet(receipt: .preview)
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: "vi"))
        .preferredColorScheme(.dark)
}
