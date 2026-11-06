import Foundation

/// What an expense was for. The app gives each one a name, a symbol and a color, and shows them
/// in this order: everyday spending first, then the home, things bought, the person, other
/// people, and money matters.
///
/// Only spending: money moved between the person's own accounts, cash, savings, investments or
/// e-wallets isn't an expense, since it's still theirs (see `Asset`), and nor is income.
///
/// The raw values are what the database and iCloud store, so don't rename them. Adding one means
/// a new `LedgerDatabase.RecordVersion.entry`, so an earlier version of the app, which reads it as
/// `other`, shows the entry without saving over it.
public enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
    case food
    case drinks
    case groceries
    case transport
    case vehicle
    case housing
    case household
    case bills
    case subscriptions
    case shopping
    case fashion
    case electronics
    case beauty
    case health
    case fitness
    case insurance
    case education
    case entertainment
    case travel
    case family
    case kids
    case pets
    case gifts
    case charity
    case worship
    case fees
    case loans
    case other

    /// Reads a category the app doesn't have, such as one a later version added, as `other`, so
    /// one unknown value doesn't make the whole ledger unreadable.
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ExpenseCategory(rawValue: rawValue) ?? .other
    }
}
