#if DEBUG
import RiengtuKit
import SwiftUI

extension Ledger {
    /// A few days of spending in two currencies, and some of every kind of asset.
    static let preview: Ledger = {
        let calendar = Calendar.current
        func daysAgo(_ days: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: .now)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }
        return Ledger(expenses: [
            Expense(amount: 45_000, currencyCode: "VND", category: .food, date: daysAgo(0, hour: 8), note: "Phở bò"),
            Expense(amount: 32_000, currencyCode: "VND", category: .transport, date: daysAgo(0, hour: 9)),
            Expense(amount: 1_250_000, currencyCode: "VND", category: .groceries, date: daysAgo(1, hour: 18), note: "Co.op Mart"),
            Expense(amount: Decimal(string: "12.5")!, currencyCode: "USD", category: .entertainment, date: daysAgo(3, hour: 20), note: "Streaming"),
            Expense(amount: 500_000, currencyCode: "VND", category: .gifts, date: daysAgo(40, hour: 11), note: "Đám cưới Lan"),
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
        ], recentCurrencyCodes: ["VND", "USD"])
    }()
}

extension View {
    /// The environment the app's views need, with `ledger` in memory and the lock off.
    func previewEnvironment(_ ledger: Ledger = .preview) -> some View {
        environment(LedgerStore(inMemory: ledger))
            .environment(AppLock(defaults: UserDefaults(suiteName: "preview")!))
    }
}
#endif
