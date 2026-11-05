import Foundation

/// Money spent once: how much, in which currency, on what, and when.
public struct Expense: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Always more than zero.
    public var amount: Decimal
    /// An ISO 4217 code, such as `VND` or `USD`. Each expense keeps its own currency, and amounts
    /// in different currencies are never added together.
    public var currencyCode: String
    public var category: ExpenseCategory
    public var date: Date
    /// What the person wrote about it. Empty when they wrote nothing.
    public var note: String
    /// What it was for, from the person's tags (`Ledger.tags`), in the order they were added.
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        amount: Decimal,
        currencyCode: String,
        category: ExpenseCategory,
        date: Date,
        note: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.category = category
        self.date = date
        self.note = note
        self.tags = tags
    }
}

extension Expense: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, amount, currencyCode = "currency", category, date, note, tags
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amount = try container.decodeDecimal(forKey: .amount)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        category = try container.decode(ExpenseCategory.self, forKey: .category)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeDecimal(amount, forKey: .amount)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(category, forKey: .category)
        try container.encode(date, forKey: .date)
        if !note.isEmpty {
            try container.encode(note, forKey: .note)
        }
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
    }
}
