import Foundation

/// Money in or out that Riengtu picked up from outside the app, such as from a bank's email or
/// an Apple Pay payment, waiting in the inbox for the person to add to the ledger or dismiss.
public struct CapturedTransaction: Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// A bank's email or message, read by `TransactionText`.
        case bankMessage
        /// A payment with its amount already known, such as from an Apple Pay automation.
        case payment
    }

    public var id: UUID
    public var source: Source
    public var capturedAt: Date
    /// When the money moved, if the message says, or else when it was captured.
    public var date: Date
    /// `nil` when the message doesn't say clearly.
    public var amount: Decimal?
    public var currencyCode: String?
    /// Whether the money came in, such as a transfer received, rather than going out.
    public var isMoneyIn: Bool
    /// Who was paid or who paid, or what for. Empty when the message doesn't say.
    public var description: String
    /// The message as it came, kept until the transaction is added or dismissed so the person
    /// can check it. Empty for payments.
    public var text: String
    /// Whether Apple Intelligence has read `text` yet.
    public var wasRead: Bool

    public init(
        id: UUID = UUID(),
        source: Source,
        capturedAt: Date,
        date: Date,
        amount: Decimal?,
        currencyCode: String?,
        isMoneyIn: Bool = false,
        description: String,
        text: String = "",
        wasRead: Bool = false
    ) {
        self.id = id
        self.source = source
        self.capturedAt = capturedAt
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.isMoneyIn = isMoneyIn
        self.description = description
        self.text = text
        self.wasRead = wasRead
    }
}

extension CapturedTransaction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, source, capturedAt, date, amount, currencyCode = "currency", isMoneyIn = "moneyIn", description, text, wasRead
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(Source.self, forKey: .source)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        date = try container.decode(Date.self, forKey: .date)
        amount = try container.decodeDecimalIfPresent(forKey: .amount)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
        isMoneyIn = try container.decodeIfPresent(Bool.self, forKey: .isMoneyIn) ?? false
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        wasRead = try container.decodeIfPresent(Bool.self, forKey: .wasRead) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(date, forKey: .date)
        try container.encodeDecimalIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        if isMoneyIn { try container.encode(isMoneyIn, forKey: .isMoneyIn) }
        if !description.isEmpty { try container.encode(description, forKey: .description) }
        if !text.isEmpty { try container.encode(text, forKey: .text) }
        if wasRead { try container.encode(wasRead, forKey: .wasRead) }
    }
}
