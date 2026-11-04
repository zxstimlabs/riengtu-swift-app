import Foundation

/// What an expense was for. The app gives each one a name, a symbol and a color.
///
/// The raw values are what the ledger file stores, so don't rename them.
public enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
    case food
    case groceries
    case transport
    case shopping
    case housing
    case bills
    case health
    case education
    case entertainment
    case travel
    case family
    case gifts
    case other

    /// Reads a category the app doesn't have, such as one a later version added, as `other`, so
    /// one unknown value doesn't make the whole ledger unreadable.
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: rawValue) ?? .other
    }
}
