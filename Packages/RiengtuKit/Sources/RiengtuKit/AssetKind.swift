import Foundation

/// What an asset is. The kind decides how its value is worked out, and the app gives each one a
/// name, a symbol and a color.
///
/// The raw values are what the ledger file stores, so don't rename them.
public enum AssetKind: String, CaseIterable, Codable, Sendable {
    case cash
    case bankAccount
    case eWallet
    /// A term deposit at a bank (tiền gửi tiết kiệm).
    case savings
    /// Shares, such as ones listed on HOSE, HNX or UPCoM.
    case stock
    /// Fund certificates (chứng chỉ quỹ), including ETFs.
    case fund
    case gold
    case crypto
    case property
    case vehicle
    case other

    /// Reads a kind the app doesn't have, such as one a later version added, as `other`, so one
    /// unknown value doesn't make the whole ledger unreadable. The asset keeps its value.
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AssetKind(rawValue: rawValue) ?? .other
    }

    /// The groups the app lists assets in.
    public enum Group: CaseIterable, Sendable {
        /// Cash, accounts and deposits.
        case money
        /// Things bought for their price, which changes: shares, fund certificates, gold, coins.
        case investments
        /// Property, vehicles and other belongings.
        case things
    }

    public var group: Group {
        switch self {
        case .cash, .bankAccount, .eWallet, .savings: .money
        case .stock, .fund, .gold, .crypto: .investments
        case .property, .vehicle, .other: .things
        }
    }

    /// The kinds in `group`, in the order the app lists them.
    public static func kinds(in group: Group) -> [AssetKind] {
        allCases.filter { $0.group == group }
    }

    /// How an asset of a kind is valued.
    public enum Valuation: Sendable {
        /// One amount: a balance, or what the thing would sell for.
        case amount
        /// A quantity times the price of one: shares, fund units or coins.
        case holding
        /// A weight of gold times its price by weight.
        case gold
    }

    public var valuation: Valuation {
        switch self {
        case .cash, .bankAccount, .eWallet, .savings, .property, .vehicle, .other: .amount
        case .stock, .fund, .crypto: .holding
        case .gold: .gold
        }
    }

    /// How many digits a quantity of this kind can have after the decimal separator.
    public var quantityFractionDigits: Int {
        self == .crypto ? 8 : 4
    }
}

/// The units gold is weighed and priced in, in Vietnam.
///
/// The raw values are what the ledger file stores, so don't rename them.
public enum GoldUnit: String, CaseIterable, Codable, Sendable {
    /// 37.5 grams, also called a cây, or a tael in English. Gold prices are usually given per lượng.
    case luong
    /// A tenth of a lượng, 3.75 grams.
    case chi
    case gram

    public var grams: Decimal {
        switch self {
        case .luong: Decimal(375) / 10
        case .chi: Decimal(375) / 100
        case .gram: 1
        }
    }
}
