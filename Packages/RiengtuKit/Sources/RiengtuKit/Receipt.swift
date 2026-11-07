import Foundation

/// What a receipt says, read from a photo of it (`ReceiptReader`) and kept with its entry: the
/// shop, when, each item, and the totals. The photo itself isn't kept, by the user's choice: it's
/// read on the device and let go.
public struct Receipt: Hashable, Sendable {
    /// One line of what was bought.
    public struct Item: Hashable, Sendable {
        public var name: String
        public var quantity: Decimal?
        /// The price of one.
        public var unitPrice: Decimal?
        /// What the line came to.
        public var amount: Decimal?

        public init(name: String, quantity: Decimal? = nil, unitPrice: Decimal? = nil, amount: Decimal? = nil) {
            self.name = name
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.amount = amount
        }
    }

    /// The shop's or restaurant's name, as printed.
    public var merchant: String
    public var address: String
    /// When it was printed, if it says.
    public var date: Date?
    public var items: [Item]
    public var subtotal: Decimal?
    public var discount: Decimal?
    /// VAT or another tax.
    public var tax: Decimal?
    /// What was paid in all.
    public var total: Decimal?
    /// An ISO 4217 code, which all its amounts are in.
    public var currencyCode: String
    /// Its number, or the payment's reference, as printed: "00012345", "VQR-20260714-8842".
    public var reference: String
    /// How it was paid, as printed: "Tiền mặt", "Thẻ Visa", "VietQR".
    public var paymentMethod: String

    public init(
        merchant: String = "", address: String = "", date: Date? = nil, items: [Item] = [], subtotal: Decimal? = nil,
        discount: Decimal? = nil, tax: Decimal? = nil, total: Decimal? = nil, currencyCode: String,
        reference: String = "", paymentMethod: String = ""
    ) {
        self.merchant = merchant
        self.address = address
        self.date = date
        self.items = items
        self.subtotal = subtotal
        self.discount = discount
        self.tax = tax
        self.total = total
        self.currencyCode = currencyCode
        self.reference = reference
        self.paymentMethod = paymentMethod
    }

    /// Whether nothing was read from it.
    public var isEmpty: Bool {
        merchant.isEmpty && items.isEmpty && total == nil
    }
}

extension Receipt: Codable {
    private enum CodingKeys: String, CodingKey {
        case merchant, address, date, items, subtotal, discount, tax, total, currencyCode = "currency"
        case reference, paymentMethod = "payment"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        subtotal = try container.decodeDecimalIfPresent(forKey: .subtotal)
        discount = try container.decodeDecimalIfPresent(forKey: .discount)
        tax = try container.decodeDecimalIfPresent(forKey: .tax)
        total = try container.decodeDecimalIfPresent(forKey: .total)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        reference = try container.decodeIfPresent(String.self, forKey: .reference) ?? ""
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !merchant.isEmpty { try container.encode(merchant, forKey: .merchant) }
        if !address.isEmpty { try container.encode(address, forKey: .address) }
        try container.encodeIfPresent(date, forKey: .date)
        if !items.isEmpty { try container.encode(items, forKey: .items) }
        try container.encodeDecimalIfPresent(subtotal, forKey: .subtotal)
        try container.encodeDecimalIfPresent(discount, forKey: .discount)
        try container.encodeDecimalIfPresent(tax, forKey: .tax)
        try container.encodeDecimalIfPresent(total, forKey: .total)
        try container.encode(currencyCode, forKey: .currencyCode)
        if !reference.isEmpty { try container.encode(reference, forKey: .reference) }
        if !paymentMethod.isEmpty { try container.encode(paymentMethod, forKey: .paymentMethod) }
    }
}

extension Receipt.Item: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, quantity, unitPrice = "price", amount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        quantity = try container.decodeDecimalIfPresent(forKey: .quantity)
        unitPrice = try container.decodeDecimalIfPresent(forKey: .unitPrice)
        amount = try container.decodeDecimalIfPresent(forKey: .amount)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeDecimalIfPresent(quantity, forKey: .quantity)
        try container.encodeDecimalIfPresent(unitPrice, forKey: .unitPrice)
        try container.encodeDecimalIfPresent(amount, forKey: .amount)
    }
}
