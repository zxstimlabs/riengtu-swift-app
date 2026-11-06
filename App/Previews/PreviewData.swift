import RiengtuKit
import SwiftUI

// Not behind `#if DEBUG`: `#Preview` blocks are compiled in Release builds too, and they use
// this. Only previews read it.

extension Ledger {
    /// A few days of spending and income in two currencies, with tags, a transfer and a change
    /// to an asset's value, and some of every kind of asset.
    static let preview: Ledger = {
        let calendar = Calendar.current
        func daysAgo(_ days: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: .now)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }
        let wallet = Asset(kind: .cash, name: "Ví", currencyCode: "VND", value: .amount(3_455_000), valuedAt: daysAgo(2, hour: 9))
        let vietcombank = Asset(kind: .bankAccount, name: "Vietcombank", currencyCode: "VND", value: .amount(108_000_000), valuedAt: daysAgo(1, hour: 9))
        let momo = Asset(kind: .eWallet, name: "MoMo", currencyCode: "VND", value: .amount(1_250_000), valuedAt: daysAgo(1, hour: 9))
        let fpt = Asset(kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 500, price: 118_000), valuedAt: daysAgo(0, hour: 15))
        return Ledger(entries: [
            Entry(kind: .expense(.food, account: wallet.id), amount: 45_000, currencyCode: "VND", date: daysAgo(0, hour: 8), note: "Phở bò", tags: ["Personal"]),
            Entry(kind: .expense(.transport, account: momo.id), amount: 32_000, currencyCode: "VND", date: daysAgo(0, hour: 9), note: "Grab đi làm", tags: ["Work"]),
            Entry(kind: .income(.salary, account: vietcombank.id), amount: 25_000_000, currencyCode: "VND", date: daysAgo(0, hour: 10), note: "Lương tháng này"),
            Entry(
                kind: .transfer(from: Entry.Leg(asset: vietcombank.id, change: 2_000_000), to: Entry.Leg(asset: wallet.id, change: 2_000_000)),
                amount: 2_000_000, currencyCode: "VND", date: daysAgo(1, hour: 12), note: "Rút tiền ATM"
            ),
            Entry(kind: .expense(.groceries, account: nil), amount: 1_250_000, currencyCode: "VND", date: daysAgo(1, hour: 18), note: "Co.op Mart", tags: ["Family"]),
            Entry(kind: .adjustment(asset: fpt.id, isIncrease: true), amount: 1_500_000, currencyCode: "VND", date: daysAgo(2, hour: 15)),
            Entry(kind: .expense(.subscriptions, account: nil), amount: Decimal(string: "12.5")!, currencyCode: "USD", date: daysAgo(3, hour: 20), note: "Streaming"),
            Entry(kind: .expense(.gifts, account: nil), amount: 500_000, currencyCode: "VND", date: daysAgo(40, hour: 11), note: "Đám cưới Lan", tags: ["Gift"]),
        ], assets: [
            wallet,
            Asset(kind: .cash, currencyCode: "USD", value: .amount(300), valuedAt: daysAgo(30, hour: 9)),
            vietcombank,
            momo,
            Asset(kind: .savings, name: "Techcombank 12 tháng", currencyCode: "VND", value: .amount(200_000_000), valuedAt: daysAgo(60, hour: 9)),
            fpt,
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
    /// A transfer from a bank's email, money received, and an Apple Pay payment, waiting in the
    /// inbox.
    static let preview: [CapturedTransaction] = [
        CapturedTransaction(
            source: .bankMessage, capturedAt: .now, date: .now.addingTimeInterval(-1_800),
            amount: 150_000, currencyCode: "VND", description: "Chuyen tien an trua",
            text: "Số tiền giao dịch: -150,000 VND\nNội dung giao dịch: CHUYEN TIEN AN TRUA"
        ),
        CapturedTransaction(
            source: .bankMessage, capturedAt: .now, date: .now.addingTimeInterval(-3_600),
            amount: 200_000, currencyCode: "VND", isMoneyIn: true, description: "Tra tien cafe",
            text: "TK 0123 +200,000 VND. ND: Tra tien cafe"
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
        let store = LedgerStore(inMemory: ledger)
        return environment(store)
            .environment(CloudSync(store: store, defaults: UserDefaults(suiteName: "preview")!))
            .environment(InboxStore(inMemory: inbox))
            .environment(AppLock(defaults: UserDefaults(suiteName: "preview")!))
    }
}
