import Foundation

/// Everything Riengtu keeps: the person's expenses, newest first, and the currencies they use.
public struct Ledger: Codable, Equatable, Sendable {
    /// The file format's version. A ledger from a later version isn't read, so this one can't
    /// overwrite data it doesn't understand.
    public static let currentVersion = 1

    /// How many recently used currencies the ledger remembers.
    public static let recentCurrencyLimit = 5

    public private(set) var version: Int
    /// Newest first. Expenses on the same date keep the order they were added, latest first.
    public private(set) var expenses: [Expense]
    /// The currencies of the expenses saved most recently, most recent first.
    public private(set) var recentCurrencyCodes: [String]

    public init(expenses: [Expense] = [], recentCurrencyCodes: [String] = []) {
        version = Self.currentVersion
        self.expenses = expenses.sorted { $0.date > $1.date }
        self.recentCurrencyCodes = Array(recentCurrencyCodes.prefix(Self.recentCurrencyLimit))
    }

    public func expense(id: Expense.ID) -> Expense? {
        expenses.first { $0.id == id }
    }

    /// Adds the expense, or replaces the one with the same ID, and remembers its currency.
    public mutating func save(_ expense: Expense) {
        expenses.removeAll { $0.id == expense.id }
        let index = expenses.firstIndex { $0.date <= expense.date } ?? expenses.endIndex
        expenses.insert(expense, at: index)

        recentCurrencyCodes.removeAll { $0 == expense.currencyCode }
        recentCurrencyCodes.insert(expense.currencyCode, at: 0)
        if recentCurrencyCodes.count > Self.recentCurrencyLimit {
            recentCurrencyCodes.removeLast(recentCurrencyCodes.count - Self.recentCurrencyLimit)
        }
    }

    public mutating func deleteExpense(id: Expense.ID) {
        expenses.removeAll { $0.id == id }
    }

    /// The currency a new expense starts in: the one used last, or `fallback` before there is one.
    public func preferredCurrencyCode(fallback: String) -> String {
        recentCurrencyCodes.first ?? fallback
    }

    /// The expenses grouped by the day they're on in `calendar`, newest day first.
    public func days(in calendar: Calendar) -> [Day] {
        var days: [Day] = []
        for expense in expenses {
            let start = calendar.startOfDay(for: expense.date)
            if days.last?.date == start {
                days[days.count - 1].expenses.append(expense)
            } else {
                days.append(Day(date: start, expenses: [expense]))
            }
        }
        return days
    }

    /// One day's expenses, newest first.
    public struct Day: Identifiable, Equatable, Sendable {
        /// The start of the day.
        public var date: Date
        public var expenses: [Expense]

        public var id: Date { date }
    }
}
