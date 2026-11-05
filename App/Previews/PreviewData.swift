import RiengtuKit
import SwiftUI

// Not behind `#if DEBUG`: `#Preview` blocks are compiled in Release builds too, and they use
// this. Only previews read it.

extension Ledger {
    /// A few days of spending in two currencies, with tags, and some of every kind of asset.
    static let preview: Ledger = {
        let calendar = Calendar.current
        func daysAgo(_ days: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: .now)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }
        return Ledger(expenses: [
            Expense(amount: 45_000, currencyCode: "VND", category: .food, date: daysAgo(0, hour: 8), note: "Phở bò", tags: ["Personal"]),
            Expense(amount: 32_000, currencyCode: "VND", category: .transport, date: daysAgo(0, hour: 9), note: "Grab đi làm", tags: ["Work"]),
            Expense(amount: 1_250_000, currencyCode: "VND", category: .groceries, date: daysAgo(1, hour: 18), note: "Co.op Mart", tags: ["Family"]),
            Expense(amount: Decimal(string: "12.5")!, currencyCode: "USD", category: .entertainment, date: daysAgo(3, hour: 20), note: "Streaming"),
            Expense(amount: 500_000, currencyCode: "VND", category: .gifts, date: daysAgo(40, hour: 11), note: "Đám cưới Lan", tags: ["Gift"]),
        ], assets: [
            Asset(kind: .cash, name: "Ví", currencyCode: "VND", value: .amount(3_500_000), valuedAt: daysAgo(2, hour: 9)),
            Asset(kind: .cash, currencyCode: "USD", value: .amount(300), valuedAt: daysAgo(30, hour: 9)),
            Asset(kind: .bankAccount, name: "Vietcombank", currencyCode: "VND", value: .amount(85_000_000), valuedAt: daysAgo(1, hour: 9)),
            Asset(kind: .eWallet, name: "MoMo", currencyCode: "VND", value: .amount(1_250_000), valuedAt: daysAgo(1, hour: 9)),
            Asset(kind: .savings, name: "Techcombank 12 tháng", currencyCode: "VND", value: .amount(200_000_000), valuedAt: daysAgo(60, hour: 9)),
            Asset(kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 500, price: 118_000), valuedAt: daysAgo(0, hour: 15)),
            Asset(kind: .stock, name: "HPG", currencyCode: "VND", value: .holding(quantity: 2_000, price: 26_500), valuedAt: daysAgo(0, hour: 15)),
            Asset(kind: .fund, name: "E1VFVN30", currencyCode: "VND", value: .holding(quantity: 1_000, price: 28_150), valuedAt: daysAgo(3, hour: 15)),
            Asset(kind: .gold, name: "SJC", currencyCode: "VND", value: .gold(weight: 2, unit: .luong, price: 148_500_000, priceUnit: .luong), valuedAt: daysAgo(0, hour: 10)),
            Asset(kind: .gold, name: "Nhẫn 9999", currencyCode: "VND", value: .gold(weight: 5, unit: .chi, price: 146_000_000, priceUnit: .luong), valuedAt: daysAgo(0, hour: 10)),
            Asset(kind: .crypto, name: "BTC", currencyCode: "USD", value: .holding(quantity: Decimal(string: "0.05")!, price: 68_000), valuedAt: daysAgo(5, hour: 20)),
            Asset(kind: .property, name: "Căn hộ Thủ Đức", currencyCode: "VND", value: .amount(3_200_000_000), valuedAt: daysAgo(90, hour: 9)),
            Asset(kind: .vehicle, name: "Honda Vision", currencyCode: "VND", value: .amount(28_000_000), valuedAt: daysAgo(90, hour: 9)),
        ], recentCurrencyCodes: ["VND", "USD"], tags: ["Personal", "Family", "Work", "Gift", "Trip"])
    }()
}

extension CapturedTransaction {
    /// A transfer from a bank's email and an Apple Pay payment, waiting in the inbox.
    static let preview: [CapturedTransaction] = [
        CapturedTransaction(
            source: .bankMessage, capturedAt: .now, date: .now.addingTimeInterval(-1_800),
            amount: 150_000, currencyCode: "VND", description: "Chuyen tien an trua",
            text: "Số tiền giao dịch: -150,000 VND\nNội dung giao dịch: CHUYEN TIEN AN TRUA"
        ),
        CapturedTransaction(
            source: .payment, capturedAt: .now, date: .now.addingTimeInterval(-7_200),
            amount: 65_000, currencyCode: "VND", description: "Highlands Coffee"
        ),
    ]
}

extension View {
    /// The environment the app's views need, with `ledger` and `inbox` in memory and the lock off.
    func previewEnvironment(_ ledger: Ledger = .preview, inbox: [CapturedTransaction] = CapturedTransaction.preview) -> some View {
        environment(LedgerStore(inMemory: ledger))
            .environment(InboxStore(inMemory: inbox))
            .environment(AppLock(defaults: UserDefaults(suiteName: "preview")!))
    }
}
