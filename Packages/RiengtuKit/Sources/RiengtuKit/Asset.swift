import Foundation

/// Something the person owns, and what it's worth in one currency.
///
/// Prices are typed in, so `valuedAt` says how old the value is.
public struct Asset: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: AssetKind
    /// What the person calls it, such as a bank's name. For shares, fund certificates and coins,
    /// the ticker, such as `FPT`. Empty when they gave none.
    public var name: String
    /// An ISO 4217 code, such as `VND`. Assets in different currencies are never added together.
    public var currencyCode: String
    public var value: Value
    /// When the amount or price was last set.
    public var valuedAt: Date
    /// What the person wrote about it. Empty when they wrote nothing.
    public var note: String

    /// How much of something there is, and what it's worth, in the asset's currency. Never
    /// negative.
    public enum Value: Hashable, Sendable {
        /// A balance, or what the thing would sell for.
        case amount(Decimal)
        /// A number of shares, fund units or coins, and the price of one.
        case holding(quantity: Decimal, price: Decimal)
        /// A weight of gold, and its price per `priceUnit`, which can differ from the weight's unit:
        /// gold weighed in chỉ is often priced per lượng.
        case gold(weight: Decimal, unit: GoldUnit, price: Decimal, priceUnit: GoldUnit)
    }

    public init(
        id: UUID = UUID(),
        kind: AssetKind,
        name: String = "",
        currencyCode: String,
        value: Value,
        valuedAt: Date,
        note: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.currencyCode = currencyCode
        self.value = value
        self.valuedAt = valuedAt
        self.note = note
    }

    /// What it's worth, rounded to the currency's digits, so totals add up to what's shown.
    public var worth: Decimal {
        var exact: Decimal
        switch value {
        case .amount(let amount):
            exact = amount
        case .holding(let quantity, let price):
            exact = quantity * price
        case .gold(let weight, let unit, let price, let priceUnit):
            exact = weight * unit.grams * price / priceUnit.grams
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, Currencies.fractionDigits(for: currencyCode), .plain)
        return rounded
    }
}

extension Asset: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, currencyCode = "currency", valuedAt, note
        case amount
        case quantity, price
        case weight, weightUnit, priceUnit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(AssetKind.self, forKey: .kind)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        valuedAt = try container.decode(Date.self, forKey: .valuedAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""

        if container.contains(.weight) {
            value = .gold(
                weight: try container.decodeDecimal(forKey: .weight),
                unit: try container.decode(GoldUnit.self, forKey: .weightUnit),
                price: try container.decodeDecimal(forKey: .price),
                priceUnit: try container.decode(GoldUnit.self, forKey: .priceUnit)
            )
        } else if container.contains(.quantity) {
            value = .holding(
                quantity: try container.decodeDecimal(forKey: .quantity),
                price: try container.decodeDecimal(forKey: .price)
            )
        } else {
            value = .amount(try container.decodeDecimal(forKey: .amount))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if !name.isEmpty {
            try container.encode(name, forKey: .name)
        }
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(valuedAt, forKey: .valuedAt)
        if !note.isEmpty {
            try container.encode(note, forKey: .note)
        }

        switch value {
        case .amount(let amount):
            try container.encodeDecimal(amount, forKey: .amount)
        case .holding(let quantity, let price):
            try container.encodeDecimal(quantity, forKey: .quantity)
            try container.encodeDecimal(price, forKey: .price)
        case .gold(let weight, let unit, let price, let priceUnit):
            try container.encodeDecimal(weight, forKey: .weight)
            try container.encode(unit, forKey: .weightUnit)
            try container.encodeDecimal(price, forKey: .price)
            try container.encode(priceUnit, forKey: .priceUnit)
        }
    }
}
