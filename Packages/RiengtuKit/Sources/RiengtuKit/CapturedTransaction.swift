import Foundation

/// Money in or out that Riêng Tư picked up from outside the app, such as a bank's notification
/// or email, or an Apple Pay payment, waiting in the inbox for the person to add to the ledger
/// or dismiss. Once it's added or dismissed, it stays in the inbox's history, with the message as
/// it came, until the history is deleted (`InboxStore.deleteHistory(handledBefore:)`).
public struct CapturedTransaction: Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// A bank's notification, email or message, forwarded as it came, and read in the app
        /// (`InboxStore.readNewItems()`).
        case bankMessage
        /// A payment with its amount already known, such as from an Apple Pay automation.
        case payment
        /// A transaction on a screenshot of a bank app's history (`ScreenshotText`), dated by its
        /// day's heading and its time, and read as a bank's message is.
        case screenshot
        /// A row or entry of a file the person picked (`FileText`), such as a bank's export,
        /// dated by what it says, and read as a bank's message is.
        case file
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
    /// Whether the money moved between the person's own accounts, such as paying off their
    /// credit card, so it's a transfer rather than an expense or income.
    public var isTransfer: Bool
    /// The category Apple Intelligence chose, for money out or money in. `nil` when it hasn't,
    /// such as where it isn't available.
    public var expenseCategory: ExpenseCategory?
    public var incomeCategory: IncomeCategory?
    /// Who was paid or who paid, or what for. Empty when the message doesn't say.
    public var description: String
    /// The message as it came, kept with the history so the person can check what was read from
    /// it. For a payment, the amount as it came, only if it couldn't be read.
    public var text: String
    /// Whether it's been read: its message by Apple Intelligence, or by the rules where that
    /// isn't available, and its category chosen.
    public var wasRead: Bool
    /// When it was added to the ledger or dismissed, after which it's in the history. `nil`
    /// while it waits in the inbox.
    public var handledAt: Date?
    /// The entry it was added as, if it was.
    public var entryID: Entry.ID?
    /// The other message for the same money (`InboxStore.joinPairs`): for a transfer between the
    /// person's own accounts, the side that came in, joined to the side that went out; for one that
    /// came twice, the one that was kept. The one joined or left out is in the history.
    public var pairedID: CapturedTransaction.ID?

    public init(
        id: UUID = UUID(),
        source: Source,
        capturedAt: Date,
        date: Date,
        amount: Decimal?,
        currencyCode: String?,
        isMoneyIn: Bool = false,
        isTransfer: Bool = false,
        expenseCategory: ExpenseCategory? = nil,
        incomeCategory: IncomeCategory? = nil,
        description: String,
        text: String = "",
        wasRead: Bool = false,
        handledAt: Date? = nil,
        entryID: Entry.ID? = nil,
        pairedID: CapturedTransaction.ID? = nil
    ) {
        self.id = id
        self.source = source
        self.capturedAt = capturedAt
        self.date = date
        self.amount = amount
        self.currencyCode = currencyCode
        self.isMoneyIn = isMoneyIn
        self.isTransfer = isTransfer
        self.expenseCategory = expenseCategory
        self.incomeCategory = incomeCategory
        self.description = description
        self.text = text
        self.wasRead = wasRead
        self.handledAt = handledAt
        self.entryID = entryID
        self.pairedID = pairedID
    }

    /// Whether it's waiting in the inbox, rather than in the history.
    public var isPending: Bool { handledAt == nil }

    /// Whether Add All can add it as it is: it's been read, has an amount, and isn't a transfer,
    /// which needs its two assets chosen.
    public var isReadyToAdd: Bool {
        isPending && wasRead && amount != nil && !isTransfer
    }
}

extension CapturedTransaction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, source, capturedAt, date, amount, currencyCode = "currency", isMoneyIn = "moneyIn", isTransfer = "transfer",
             expenseCategory, incomeCategory, description, text, wasRead, handledAt = "handled", entryID = "entry"
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
        isTransfer = try container.decodeIfPresent(Bool.self, forKey: .isTransfer) ?? false
        expenseCategory = try container.decodeIfPresent(ExpenseCategory.self, forKey: .expenseCategory)
        incomeCategory = try container.decodeIfPresent(IncomeCategory.self, forKey: .incomeCategory)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        wasRead = try container.decodeIfPresent(Bool.self, forKey: .wasRead) ?? false
        handledAt = try container.decodeIfPresent(Date.self, forKey: .handledAt)
        entryID = try container.decodeIfPresent(UUID.self, forKey: .entryID)
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
        if isTransfer { try container.encode(isTransfer, forKey: .isTransfer) }
        try container.encodeIfPresent(expenseCategory, forKey: .expenseCategory)
        try container.encodeIfPresent(incomeCategory, forKey: .incomeCategory)
        if !description.isEmpty { try container.encode(description, forKey: .description) }
        if !text.isEmpty { try container.encode(text, forKey: .text) }
        if wasRead { try container.encode(wasRead, forKey: .wasRead) }
        try container.encodeIfPresent(handledAt, forKey: .handledAt)
        try container.encodeIfPresent(entryID, forKey: .entryID)
    }
}
