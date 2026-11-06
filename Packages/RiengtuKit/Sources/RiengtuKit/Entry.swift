import Foundation

/// One line in the ledger: money that went out or came in, money moved between the person's own
/// assets, or a change to an asset's value.
public struct Entry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: Kind
    /// Always more than zero, in `currencyCode`. For a transfer, the money that moved; for an
    /// adjustment, how much the asset's worth changed.
    public var amount: Decimal
    /// An ISO 4217 code, such as `VND` or `USD`. Each entry keeps its own currency, and amounts
    /// in different currencies are never added together.
    public var currencyCode: String
    public var date: Date
    /// What the person wrote about it. Empty when they wrote nothing.
    public var note: String
    /// What it was for, from the person's tags (`Ledger.tags`), in the order they were added.
    public var tags: [String]

    public enum Kind: Hashable, Sendable {
        /// Money spent, from `account` if the person said which: its balance goes down by the
        /// amount, which is in the account's currency.
        case expense(ExpenseCategory, account: Asset.ID?)
        /// Money received, into `account` if the person said which: its balance goes up by the
        /// amount, which is in the account's currency.
        case income(IncomeCategory, account: Asset.ID?)
        /// Money moved between the person's own assets, such as cash taken out at an ATM, a
        /// savings deposit, or shares or gold bought or sold. It isn't spending or income. A leg
        /// is `nil` once its asset is deleted.
        case transfer(from: Leg?, to: Leg?)
        /// A change to an asset's value typed in by hand, such as a corrected balance or a new
        /// price. Only a record: the asset changed already, and deleting the entry doesn't change
        /// it back.
        case adjustment(asset: Asset.ID, isIncrease: Bool)
    }

    /// One side of a transfer: an asset, and how much it went down (`from`) or up (`to`).
    public struct Leg: Hashable, Sendable {
        public var asset: Asset.ID
        /// More than zero, in the asset's own terms: money in its currency for an asset valued by
        /// an amount, or a number of shares, units or coins, or a weight of gold in the asset's
        /// unit.
        public var change: Decimal

        public init(asset: Asset.ID, change: Decimal) {
            self.asset = asset
            self.change = change
        }
    }

    public init(
        id: UUID = UUID(),
        kind: Kind,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        note: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.note = note
        self.tags = tags
    }

    /// Whether the entry is income, spending, or neither, as the month's totals count it.
    public enum Flow: Sendable {
        case moneyIn, moneyOut, neither
    }

    public var flow: Flow {
        switch kind {
        case .income: .moneyIn
        case .expense: .moneyOut
        case .transfer, .adjustment: .neither
        }
    }

    /// How the entry changes the person's assets: each asset, and how much it goes up (or down,
    /// below zero) in its own terms. An adjustment changes none: the asset changed already.
    public var assetChanges: [(asset: Asset.ID, change: Decimal)] {
        switch kind {
        case .expense(_, let account?):
            [(account, -amount)]
        case .income(_, let account?):
            [(account, amount)]
        case .transfer(let from, let to):
            (from.map { [($0.asset, -$0.change)] } ?? []) + (to.map { [($0.asset, $0.change)] } ?? [])
        case .expense, .income, .adjustment:
            []
        }
    }

    /// Whether the entry involves the asset at all, including as a record of its change.
    public func involves(_ asset: Asset.ID) -> Bool {
        if case .adjustment(asset, _) = kind { return true }
        return assetChanges.contains { $0.asset == asset }
    }
}

extension Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, type, amount, currencyCode = "currency", date, note, tags
        case category, account
        case from, fromChange, to, toChange
        case asset, increase
    }

    /// What kind of entry it is, in the file. Before version 5 every entry was an expense, with
    /// no type.
    private enum EntryType: String, Codable {
        case expense, income, transfer, adjustment
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amount = try container.decodeDecimal(forKey: .amount)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []

        switch try container.decodeIfPresent(EntryType.self, forKey: .type) ?? .expense {
        case .expense:
            kind = .expense(
                try container.decode(ExpenseCategory.self, forKey: .category),
                account: try container.decodeIfPresent(UUID.self, forKey: .account)
            )
        case .income:
            kind = .income(
                try container.decode(IncomeCategory.self, forKey: .category),
                account: try container.decodeIfPresent(UUID.self, forKey: .account)
            )
        case .transfer:
            func leg(_ asset: CodingKeys, _ change: CodingKeys) throws -> Leg? {
                guard let id = try container.decodeIfPresent(UUID.self, forKey: asset) else { return nil }
                return Leg(asset: id, change: try container.decodeDecimal(forKey: change))
            }
            kind = .transfer(from: try leg(.from, .fromChange), to: try leg(.to, .toChange))
        case .adjustment:
            kind = .adjustment(
                asset: try container.decode(UUID.self, forKey: .asset),
                isIncrease: try container.decode(Bool.self, forKey: .increase)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeDecimal(amount, forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(date, forKey: .date)
        if !note.isEmpty {
            try container.encode(note, forKey: .note)
        }
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }

        switch kind {
        case .expense(let category, let account):
            try container.encode(EntryType.expense, forKey: .type)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(account, forKey: .account)
        case .income(let category, let account):
            try container.encode(EntryType.income, forKey: .type)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(account, forKey: .account)
        case .transfer(let from, let to):
            try container.encode(EntryType.transfer, forKey: .type)
            if let from {
                try container.encode(from.asset, forKey: .from)
                try container.encodeDecimal(from.change, forKey: .fromChange)
            }
            if let to {
                try container.encode(to.asset, forKey: .to)
                try container.encodeDecimal(to.change, forKey: .toChange)
            }
        case .adjustment(let asset, let isIncrease):
            try container.encode(EntryType.adjustment, forKey: .type)
            try container.encode(asset, forKey: .asset)
            try container.encode(isIncrease, forKey: .increase)
        }
    }
}
