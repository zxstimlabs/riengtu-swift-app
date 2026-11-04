import Foundation

/// Everything Riengtu keeps: the person's expenses, newest first, what they own, and the
/// currencies they spend in.
public struct Ledger: Equatable, Sendable {
    /// The file format's version. A ledger from a later version isn't read, so this one can't
    /// overwrite data it doesn't understand.
    ///
    /// - 1: expenses.
    /// - 2: assets too. A version 1 file reads as having none.
    public static let currentVersion = 2

    /// How many recently used currencies the ledger remembers.
    public static let recentCurrencyLimit = 5

    /// Newest first. Expenses on the same date keep the order they were added, latest first.
    public private(set) var expenses: [Expense]
    /// In the order they were added.
    public private(set) var assets: [Asset]
    /// The currencies of the expenses saved most recently, most recent first. Assets don't
    /// change it, so the currency a new expense starts in is always one the person spent in.
    public private(set) var recentCurrencyCodes: [String]

    public init(expenses: [Expense] = [], assets: [Asset] = [], recentCurrencyCodes: [String] = []) {
        self.expenses = expenses.sorted { $0.date > $1.date }
        self.assets = assets
        self.recentCurrencyCodes = Array(recentCurrencyCodes.prefix(Self.recentCurrencyLimit))
    }

    // MARK: Expenses

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

    // MARK: Assets

    public func asset(id: Asset.ID) -> Asset? {
        assets.first { $0.id == id }
    }

    /// Adds the asset, or replaces the one with the same ID where it is.
    public mutating func save(_ asset: Asset) {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        } else {
            assets.append(asset)
        }
    }

    public mutating func deleteAsset(id: Asset.ID) {
        assets.removeAll { $0.id == id }
    }

    /// The assets in each group that has any, in the groups' order. Within a group, they're in
    /// the kinds' order, then by name.
    public var assetSections: [AssetSection] {
        let order = Dictionary(uniqueKeysWithValues: AssetKind.allCases.enumerated().map { ($1, $0) })
        let sorted = assets.sorted { a, b in
            if a.kind != b.kind { return order[a.kind]! < order[b.kind]! }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return AssetKind.Group.allCases.compactMap { group in
            let assets = sorted.filter { $0.kind.group == group }
            return assets.isEmpty ? nil : AssetSection(group: group, assets: assets)
        }
    }

    /// What the assets are worth in each currency they're in. Amounts in different currencies
    /// aren't added together. The currency with the most assets comes first.
    public var assetTotals: [Total] {
        var totals: [String: (amount: Decimal, count: Int)] = [:]
        for asset in assets {
            totals[asset.currencyCode, default: (0, 0)].amount += asset.worth
            totals[asset.currencyCode, default: (0, 0)].count += 1
        }
        return totals
            .sorted { a, b in a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key }
            .map { Total(currencyCode: $0.key, amount: $0.value.amount) }
    }

    /// One group's assets.
    public struct AssetSection: Identifiable, Equatable, Sendable {
        public var group: AssetKind.Group
        public var assets: [Asset]

        public var id: AssetKind.Group { group }
    }

    /// An amount in one currency.
    public struct Total: Identifiable, Equatable, Sendable {
        public var currencyCode: String
        public var amount: Decimal

        public var id: String { currencyCode }
    }
}

extension Ledger: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, expenses, assets, recentCurrencyCodes
    }

    /// Reads a ledger of this version or an earlier one. `LedgerFile` checks the version first.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expenses = try container.decode([Expense].self, forKey: .expenses)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        recentCurrencyCodes = try container.decode([String].self, forKey: .recentCurrencyCodes)
    }

    /// Always writes the current version, so an earlier version of Riengtu won't read it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(expenses, forKey: .expenses)
        try container.encode(assets, forKey: .assets)
        try container.encode(recentCurrencyCodes, forKey: .recentCurrencyCodes)
    }
}
