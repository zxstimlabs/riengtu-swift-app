import Foundation

/// Where money that came in was from. The app gives each one a name, a symbol and a color, and
/// shows them in this order: pay first, then other earnings, then money from other people.
///
/// Only income: money moved from the person's own accounts, cash, savings or investments isn't,
/// since it was theirs already. That's a transfer (`Entry.Kind.transfer`).
///
/// The raw values are what the database and iCloud store, so don't rename them. Adding one means
/// a new `LedgerDatabase.RecordVersion.entry`, so an earlier version of the app, which reads it as
/// `other`, shows the entry without saving over it.
public enum IncomeCategory: String, CaseIterable, Codable, Sendable {
    case salary
    /// Including the 13th month's pay and Tết bonuses.
    case bonus
    /// Takings from the person's own shop or business.
    case business
    /// Freelance work and jobs on the side.
    case sideJob
    /// Interest on savings, and dividends.
    case investment
    /// Rent from property the person lets.
    case rental
    /// Presents, and lucky money (lì xì) at Tết or weddings.
    case gifts
    /// Money from parents or relatives.
    case family
    /// Refunds and cashback.
    case refunds
    /// Things sold that weren't kept as assets, such as used goods.
    case selling
    case other

    /// Reads a category the app doesn't have, such as one a later version added, as `other`, so
    /// one unknown value doesn't make the whole ledger unreadable.
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = IncomeCategory(rawValue: rawValue) ?? .other
    }
}
