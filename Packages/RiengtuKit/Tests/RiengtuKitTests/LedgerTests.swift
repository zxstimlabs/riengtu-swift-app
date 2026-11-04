import Foundation
import Testing
@testable import RiengtuKit

struct LedgerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    static func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    static func expense(day: Int, hour: Int = 12, amount: Decimal = 50_000, currency: String = "VND") -> Expense {
        Expense(amount: amount, currencyCode: currency, category: .food, date: date(day, hour: hour))
    }

    @Test func keepsExpensesNewestFirst() {
        var ledger = Ledger()
        let middle = Self.expense(day: 2)
        let oldest = Self.expense(day: 1)
        let newest = Self.expense(day: 3)
        ledger.save(middle)
        ledger.save(oldest)
        ledger.save(newest)
        #expect(ledger.expenses.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func putsTheLatestAddedFirstOnTheSameDate() {
        var ledger = Ledger()
        let first = Self.expense(day: 2)
        var second = Self.expense(day: 2)
        second.date = first.date
        ledger.save(first)
        ledger.save(second)
        #expect(ledger.expenses.map(\.id) == [second.id, first.id])
    }

    @Test func replacesAnExpenseWithTheSameID() {
        var ledger = Ledger()
        var expense = Self.expense(day: 2)
        ledger.save(expense)
        ledger.save(Self.expense(day: 1))

        expense.amount = 75_000
        expense.date = Self.date(4)
        ledger.save(expense)

        #expect(ledger.expenses.count == 2)
        #expect(ledger.expenses.first == expense)
        #expect(ledger.expense(id: expense.id)?.amount == 75_000)
    }

    @Test func deletesAnExpense() {
        var ledger = Ledger()
        let kept = Self.expense(day: 1)
        let deleted = Self.expense(day: 2)
        ledger.save(kept)
        ledger.save(deleted)
        ledger.deleteExpense(id: deleted.id)
        #expect(ledger.expenses == [kept])
    }

    @Test func remembersRecentCurrenciesMostRecentFirst() {
        var ledger = Ledger()
        #expect(ledger.preferredCurrencyCode(fallback: "VND") == "VND")

        for currency in ["VND", "USD", "EUR", "USD"] {
            ledger.save(Self.expense(day: 1, currency: currency))
        }
        #expect(ledger.recentCurrencyCodes == ["USD", "EUR", "VND"])
        #expect(ledger.preferredCurrencyCode(fallback: "VND") == "USD")
    }

    @Test func remembersAFewCurrencies() {
        var ledger = Ledger()
        for currency in ["VND", "USD", "EUR", "JPY", "THB", "SGD", "KRW"] {
            ledger.save(Self.expense(day: 1, currency: currency))
        }
        #expect(ledger.recentCurrencyCodes == ["KRW", "SGD", "THB", "JPY", "EUR"])
    }

    @Test func groupsExpensesByDayInTheCalendar() {
        let lateOnThe3rd = Self.expense(day: 3, hour: 23)
        let earlyOnThe3rd = Self.expense(day: 3, hour: 0)
        let onThe1st = Self.expense(day: 1)
        let ledger = Ledger(expenses: [earlyOnThe3rd, onThe1st, lateOnThe3rd])

        let days = ledger.days(in: Self.calendar)

        #expect(days.map(\.date) == [Self.date(3, hour: 0), Self.date(1, hour: 0)])
        #expect(days.map { $0.expenses.map(\.id) } == [[lateOnThe3rd.id, earlyOnThe3rd.id], [onThe1st.id]])
    }

    @Test func roundTripsThroughJSONWithoutLosingDigits() throws {
        let ledger = Ledger(expenses: [
            Expense(amount: Decimal(string: "1234567890123.4567")!, currencyCode: "USD", category: .travel, date: Self.date(1), note: "Vé máy bay"),
            Expense(amount: 0.1, currencyCode: "EUR", category: .gifts, date: Self.date(2)),
        ], recentCurrencyCodes: ["USD"])

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: data)

        #expect(decoded == ledger)
        #expect(decoded.expenses.last?.amount.description == "1234567890123.4567")
    }

    @Test func readsAnUnknownCategoryAsOther() throws {
        let json = #"["food", "pets"]"#
        let categories = try JSONDecoder().decode([ExpenseCategory].self, from: Data(json.utf8))
        #expect(categories == [.food, .other])
    }
}
