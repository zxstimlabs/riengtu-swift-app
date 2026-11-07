import Foundation
import GRDB

/// The inbox's SQLite database: one row for each `CapturedTransaction`, waiting or in the history.
///
/// Apart from the ledger's database, because the Shortcuts actions write to it in the background
/// while the device may be locked, when the ledger's can't be opened (complete file protection).
/// Its folder is protected until the person first unlocks the device after it starts: still
/// encrypted, and readable after that first unlock. Deleted rows are overwritten
/// (`secure_delete`), since the history keeps bank messages only until it's deleted.
///
/// Migrations only add tables, or columns with defaults, as in `LedgerDatabase`.
public final class InboxDatabase: Sendable {
    let queue: DatabaseQueue

    /// Opens the database in `directory`, making it if it isn't there.
    public init(directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        // Files made in the folder take its protection, the journal too.
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path(percentEncoded: false)
        )
        #endif
        queue = try DatabaseQueue(path: Self.file(in: directory).path(percentEncoded: false), configuration: Self.configuration)
        try Self.migrator.migrate(queue)
    }

    /// A database in memory, for previews and tests.
    public init() throws {
        queue = try DatabaseQueue(configuration: Self.configuration)
        try Self.migrator.migrate(queue)
    }

    public static func file(in directory: URL) -> URL {
        directory.appending(path: "inbox.sqlite")
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return configuration
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { table in
                table.primaryKey("id", .text)
                table.column("source", .text).notNull()
                // Dates are seconds since 2001, as `Date` keeps them, so they come back exactly.
                table.column("capturedAt", .double).notNull()
                table.column("date", .double).notNull()
                /// Text, such as "45000" or "12.5", so no digits are lost.
                table.column("amount", .text)
                table.column("currency", .text)
                table.column("moneyIn", .boolean).notNull().defaults(to: false)
                table.column("transfer", .boolean).notNull().defaults(to: false)
                table.column("expenseCategory", .text)
                table.column("incomeCategory", .text)
                table.column("description", .text).notNull().defaults(to: "")
                table.column("text", .text).notNull().defaults(to: "")
                table.column("wasRead", .boolean).notNull().defaults(to: false)
                table.column("handledAt", .double)
                table.column("entry", .text)
            }
            try db.create(index: "item_handledAt", on: "item", columns: ["handledAt"])
        }
        migrator.registerMigration("v2") { db in
            // `CapturedTransaction.pairedID`.
            try db.alter(table: "item") { table in
                table.add(column: "pair", .text)
            }
        }
        migrator.registerMigration("v3") { db in
            // `CapturedTransaction.isNotTransaction`, which earlier versions show as dismissed, and
            // `hint`, which they don't read.
            try db.alter(table: "item") { table in
                table.add(column: "notTransaction", .boolean).notNull().defaults(to: false)
                table.add(column: "hint", .text).notNull().defaults(to: "")
            }
        }
        return migrator
    }

    // MARK: Reading and writing

    /// Everything, newest first. A row a later version wrote that this one can't read, such as
    /// one from a new source, is left out and kept as it is.
    func items() throws -> [CapturedTransaction] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM item ORDER BY capturedAt DESC, rowid DESC")
                .compactMap { try? CapturedTransaction(row: $0) }
        }
    }

    /// Adds or replaces items.
    func save(_ items: [CapturedTransaction]) throws {
        try queue.write { db in
            for item in items {
                try item.save(db)
            }
        }
    }

    func delete(ids: [CapturedTransaction.ID]) throws {
        try queue.write { db in
            _ = try CapturedTransaction.deleteAll(db, keys: ids.map(\.uuidString))
        }
    }

    struct UnreadableRowError: Error {}

    /// Deletes what was added or dismissed before `date`, or everything in the history when
    /// it's `nil`.
    func deleteHistory(handledBefore date: Date?) throws {
        try queue.write { db in
            if let date {
                try db.execute(sql: "DELETE FROM item WHERE handledAt < ?", arguments: [date.timeIntervalSinceReferenceDate])
            } else {
                try db.execute(sql: "DELETE FROM item WHERE handledAt IS NOT NULL")
            }
        }
    }

    func deleteAll() throws {
        try queue.write { db in
            _ = try CapturedTransaction.deleteAll(db)
        }
    }
}

extension CapturedTransaction: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item"

    public init(row: Row) throws {
        let id: String = row["id"]
        let source: String = row["source"]
        let amount: String? = row["amount"]
        let expenseCategory: String? = row["expenseCategory"]
        let incomeCategory: String? = row["incomeCategory"]
        let entry: String? = row["entry"]
        let pair: String? = row["pair"]
        guard let id = UUID(uuidString: id), let source = Source(rawValue: source) else {
            throw InboxDatabase.UnreadableRowError()
        }
        self.init(
            id: id,
            source: source,
            capturedAt: Date(timeIntervalSinceReferenceDate: row["capturedAt"]),
            date: Date(timeIntervalSinceReferenceDate: row["date"]),
            amount: amount.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) },
            currencyCode: row["currency"],
            isMoneyIn: row["moneyIn"],
            isTransfer: row["transfer"],
            // A category a later version added reads as `other`.
            expenseCategory: expenseCategory.map { ExpenseCategory(rawValue: $0) ?? .other },
            incomeCategory: incomeCategory.map { IncomeCategory(rawValue: $0) ?? .other },
            description: row["description"],
            text: row["text"],
            wasRead: row["wasRead"],
            handledAt: (row["handledAt"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
            entryID: entry.flatMap(UUID.init(uuidString:)),
            pairedID: pair.flatMap(UUID.init(uuidString:)),
            isNotTransaction: row["notTransaction"],
            hint: row["hint"]
        )
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["source"] = source.rawValue
        container["capturedAt"] = capturedAt.timeIntervalSinceReferenceDate
        container["date"] = date.timeIntervalSinceReferenceDate
        container["amount"] = amount?.description
        container["currency"] = currencyCode
        container["moneyIn"] = isMoneyIn
        container["transfer"] = isTransfer
        container["expenseCategory"] = expenseCategory?.rawValue
        container["incomeCategory"] = incomeCategory?.rawValue
        container["description"] = description
        container["text"] = text
        container["wasRead"] = wasRead
        container["handledAt"] = handledAt?.timeIntervalSinceReferenceDate
        container["entry"] = entryID?.uuidString
        container["pair"] = pairedID?.uuidString
        container["notTransaction"] = isNotTransaction
        container["hint"] = hint
    }
}
