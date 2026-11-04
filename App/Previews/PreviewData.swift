#if DEBUG
import RiengtuKit
import SwiftUI

extension Ledger {
    /// A few days of spending in two currencies.
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
