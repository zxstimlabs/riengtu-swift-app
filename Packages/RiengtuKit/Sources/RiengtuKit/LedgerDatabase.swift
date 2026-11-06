import CryptoKit
import Foundation
import GRDB

/// Where the ledger is kept: a SQLite database in a folder of its own.
///
/// Each entry, asset and tag is one row of the `record` table: its JSON, the version of the
/// format it's in, and when it was last changed. That's also how it's synced, one CloudKit record
/// per row (`CloudSync`), so a later version can add fields without changing the tables, and an
/// earlier one keeps what it can't read instead of losing it. Settings that stay on the device,
/// such as the recent currencies and the sync engine's state, are in `setting`.
///
/// On iOS, the folder has complete file protection, so the database and its journal are
/// encrypted with the device's passcode and can't be opened while it's locked. Deleted rows are
/// overwritten (`secure_delete`).
///
/// Migrations must only add, such as a table or a column with a default: an earlier version of
/// Riêng Tư can open the database after a later one has, such as a TestFlight build installed
/// again, and it keeps working with the tables it knows.
public final class LedgerDatabase: Sendable {
    let queue: DatabaseQueue

    /// The database in `directory`, created if there isn't one.
    ///
    /// Throws if it can't be opened now, such as while the device is locked, or if it's damaged
    /// (`isDamaged`).
    public init(directory: URL) throws {
        let manager = FileManager.default
        #if os(iOS)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Files made in the folder take its protection, the journal too. Not `path()`, which
        // percent-encodes the space in "Application Support".
        try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path(percentEncoded: false))
        #else
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        #endif
        queue = try DatabaseQueue(path: Self.file(in: directory).path, configuration: Self.configuration)
        try Self.migrator.migrate(queue)
    }

    /// A database in memory, for tests.
    init() throws {
        queue = try DatabaseQueue(configuration: Self.configuration)
        try Self.migrator.migrate(queue)
    }

    /// The database's file in `directory`.
    static func file(in directory: URL) -> URL {
        directory.appending(path: "ledger.sqlite")
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.label = "LedgerDatabase"
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return configuration
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "record") { table in
                // Such as "entry.<UUID>", which is also the CloudKit record's name.
                table.primaryKey("name", .text)
                // The CloudKit record type: "Entry", "Asset", "Tag", or one a later version added.
                table.column("type", .text).notNull()
                table.column("version", .integer).notNull()
                // Seconds since 2001, to compare with what another device changed.
                table.column("modifiedAt", .double).notNull()
                // The record as JSON.
                table.column("data", .blob).notNull()
                // The CloudKit record's system fields, once it's been synced.
                table.column("systemFields", .blob)
                // Whether it changed here since it was last sent to iCloud.
                table.column("needsUpload", .boolean).notNull().defaults(to: false)
            }
            // Records deleted here, until iCloud deletes them too.
            try db.create(table: "tombstone") { table in
                table.primaryKey("name", .text)
            }
            try db.create(table: "setting") { table in
                table.primaryKey("key", .text)
                table.column("value", .blob).notNull()
            }
        }
        return migrator
    }

    /// Whether `error` means the database is damaged, rather than that it can't be read now.
    public static func isDamaged(_ error: any Error) -> Bool {
        guard let error = error as? DatabaseError else { return false }
        return error.resultCode == .SQLITE_CORRUPT || error.resultCode == .SQLITE_NOTADB
    }

    // MARK: Records

    /// The kinds of record, as CloudKit's record types.
    enum RecordType {
        static let entry = "Entry"
        static let asset = "Asset"
        static let tag = "Tag"
    }

    /// The version of each record's format. Raise one when an earlier version of Riêng Tư would
    /// misread or lose part of a record in the new format, such as a new kind of entry, a new
    /// category, or a new field. An earlier version then shows the record without changing it,
    /// or keeps it unread if it can't decode it.
    enum RecordVersion {
        static let entry = 1
        static let asset = 1
        static let tag = 1
    }

    static func name(ofEntry id: Entry.ID) -> String {
        "entry.\(id.uuidString)"
    }

    static func name(ofAsset id: Asset.ID) -> String {
        "asset.\(id.uuidString)"
    }

    /// The same for every spelling of the tag, so two devices that add "Work" make one record.
    /// Hashed, since record names must be ASCII.
    static func name(ofTag name: String) -> String {
        let digest = SHA256.hash(data: Data(Tags.key(name).utf8))
        return "tag." + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A tag as it's stored: its name, and its place in the list.
    struct TagRecord: Codable, Equatable {
        var name: String
        var order: Double
    }

    /// A record as it's stored and synced.
    struct Row: Equatable, Sendable {
        var name: String
        var type: String
        var version: Int
        var modifiedAt: Date
        var data: Data
        var systemFields: Data?
        var needsUpload = false

        init(name: String, type: String, version: Int, modifiedAt: Date, data: Data, systemFields: Data? = nil, needsUpload: Bool = false) {
            self.name = name
            self.type = type
            self.version = version
            self.modifiedAt = modifiedAt
            self.data = data
            self.systemFields = systemFields
            self.needsUpload = needsUpload
        }

        init(_ row: GRDB.Row) {
            name = row["name"]
            type = row["type"]
            version = row["version"]
            modifiedAt = Date(timeIntervalSinceReferenceDate: row["modifiedAt"])
            data = row["data"]
            systemFields = row["systemFields"]
            needsUpload = row["needsUpload"]
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// The ledger in the database.
    public func load() throws -> Ledger {
        try queue.read { db in
            var entries: [Entry] = []
            var assets: [Asset] = []
            var tags: [TagRecord] = []
            var newerIDs = Set<UUID>()
            var unreadable = 0
            let decoder = JSONDecoder()
            // Oldest first, so entries on the same date keep the order they were added in.
            for row in try GRDB.Row.fetchAll(db, sql: "SELECT * FROM record ORDER BY rowid").map(Row.init) {
                switch row.type {
                case RecordType.entry:
                    guard let entry = try? decoder.decode(Entry.self, from: row.data) else { unreadable += 1; continue }
                    entries.append(entry)
                    if row.version > RecordVersion.entry { newerIDs.insert(entry.id) }
                case RecordType.asset:
                    guard let asset = try? decoder.decode(Asset.self, from: row.data) else { unreadable += 1; continue }
                    assets.append(asset)
                    if row.version > RecordVersion.asset { newerIDs.insert(asset.id) }
                case RecordType.tag:
                    guard let tag = try? decoder.decode(TagRecord.self, from: row.data) else { unreadable += 1; continue }
                    tags.append(tag)
                default:
                    unreadable += 1
                }
            }
            let recentCurrencyCodes = try Self.setting(.recentCurrencyCodes, in: db)
                .flatMap { try? decoder.decode([String].self, from: $0) } ?? []
            let addedStarterTags = try Self.setting(.addedStarterTags, in: db) != nil
            let tagNames = tags.sorted { $0.order < $1.order }.map(\.name)

            var ledger = Ledger(
                entries: entries.reversed(),
                assets: assets,
                recentCurrencyCodes: recentCurrencyCodes,
                tags: addedStarterTags || !tagNames.isEmpty ? tagNames : nil
            )
            ledger.newerIDs = newerIDs
            ledger.unreadableRecordCount = unreadable
            return ledger
        }
    }

    /// The records to save and delete to make one ledger into another, and the settings that
    /// changed. Records a later version wrote aren't saved over.
    struct Changes: Sendable {
        var saved: [Row] = []
        var deleted: [String] = []
        var settings: [Setting: Data?] = [:]

        var isEmpty: Bool {
            saved.isEmpty && deleted.isEmpty && settings.isEmpty
        }

        init(from old: Ledger, to new: Ledger, now: Date = .now) throws {
            func row(_ name: String, _ type: String, _ version: Int, _ value: some Encodable) throws -> Row {
                Row(name: name, type: type, version: version, modifiedAt: now, data: try LedgerDatabase.encoder.encode(value))
            }

            let oldEntries = Dictionary(old.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Oldest first, so they're stored in the order they were added.
            for entry in new.entries.reversed() where oldEntries[entry.id] != entry && !new.newerIDs.contains(entry.id) {
                saved.append(try row(LedgerDatabase.name(ofEntry: entry.id), RecordType.entry, RecordVersion.entry, entry))
            }
            let newEntryIDs = Set(new.entries.map(\.id))
            deleted += old.entries.filter { !newEntryIDs.contains($0.id) }.map { LedgerDatabase.name(ofEntry: $0.id) }

            let oldAssets = Dictionary(old.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for asset in new.assets where oldAssets[asset.id] != asset && !new.newerIDs.contains(asset.id) {
                saved.append(try row(LedgerDatabase.name(ofAsset: asset.id), RecordType.asset, RecordVersion.asset, asset))
            }
            let newAssetIDs = Set(new.assets.map(\.id))
            deleted += old.assets.filter { !newAssetIDs.contains($0.id) }.map { LedgerDatabase.name(ofAsset: $0.id) }

            let oldTags = Dictionary(old.tags.enumerated().map { (LedgerDatabase.name(ofTag: $1), TagRecord(name: $1, order: Double($0))) }, uniquingKeysWith: { first, _ in first })
            var newTagNames = Set<String>()
            for (index, name) in new.tags.enumerated() {
                let recordName = LedgerDatabase.name(ofTag: name)
                newTagNames.insert(recordName)
                let tag = TagRecord(name: name, order: Double(index))
                if oldTags[recordName] != tag {
                    saved.append(try row(recordName, RecordType.tag, RecordVersion.tag, tag))
                }
            }
            deleted += oldTags.keys.filter { !newTagNames.contains($0) }.sorted()

            if old.recentCurrencyCodes != new.recentCurrencyCodes {
                settings[.recentCurrencyCodes] = try LedgerDatabase.encoder.encode(new.recentCurrencyCodes)
            }
            if old.needsStarterTags != new.needsStarterTags {
                settings.updateValue(new.needsStarterTags ? nil : Data([1]), forKey: .addedStarterTags)
            }
        }

        /// The names of the records saved.
        var savedNames: [String] {
            saved.map(\.name)
        }
    }

    /// Saves changes the person made, all or none, marking them for iCloud.
    func write(_ changes: Changes) throws {
        try queue.write { db in
            for row in changes.saved {
                try db.execute(
                    sql: """
                        INSERT INTO record (name, type, version, modifiedAt, data, needsUpload) VALUES (?, ?, ?, ?, ?, 1)
                        ON CONFLICT(name) DO UPDATE SET type = excluded.type, version = excluded.version,
                            modifiedAt = excluded.modifiedAt, data = excluded.data, needsUpload = 1
                        """,
                    arguments: [row.name, row.type, row.version, row.modifiedAt.timeIntervalSinceReferenceDate, row.data]
                )
                // Such as a tag deleted, then added again.
                try db.execute(sql: "DELETE FROM tombstone WHERE name = ?", arguments: [row.name])
            }
            for name in changes.deleted {
                try db.execute(sql: "DELETE FROM record WHERE name = ?", arguments: [name])
                try db.execute(sql: "INSERT OR IGNORE INTO tombstone (name) VALUES (?)", arguments: [name])
            }
            for (key, value) in changes.settings {
                try Self.setSetting(key, to: value, in: db)
            }
        }
    }

    /// Moves a ledger from the file earlier builds kept it in. Saving the same ledger again
    /// changes nothing, so it's safe to repeat if the file wasn't deleted.
    func importLedger(_ ledger: Ledger) throws {
        try write(Changes(from: Ledger(), to: ledger))
    }

    /// Deletes every record and setting.
    func eraseAll() throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM record")
            try db.execute(sql: "DELETE FROM tombstone")
            try db.execute(sql: "DELETE FROM setting")
        }
    }

    // MARK: Settings

    enum Setting: String, Sendable {
        case recentCurrencyCodes, addedStarterTags, syncState
    }

    private static func setting(_ key: Setting, in db: Database) throws -> Data? {
        try Data.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key.rawValue])
    }

    private static func setSetting(_ key: Setting, to value: Data?, in db: Database) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: [key.rawValue, value])
        } else {
            try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key.rawValue])
        }
    }

    // MARK: Sync

    /// The sync engine's state, to start it again where it stopped.
    func syncState() throws -> Data? {
        try queue.read { try Self.setting(.syncState, in: $0) }
    }

    func setSyncState(_ state: Data?) throws {
        try queue.write { try Self.setSetting(.syncState, to: state, in: $0) }
    }

    /// The records changed here that iCloud doesn't have yet, and the ones deleted here.
    func pendingChanges() throws -> (saved: [String], deleted: [String]) {
        try queue.read { db in
            (
                try String.fetchAll(db, sql: "SELECT name FROM record WHERE needsUpload ORDER BY rowid"),
                try String.fetchAll(db, sql: "SELECT name FROM tombstone")
            )
        }
    }

    /// The records with these names, by name.
    func rows(named names: some Collection<String>) throws -> [String: Row] {
        guard !names.isEmpty else { return [:] }
        return try queue.read { db in
            let rows = try GRDB.Row.fetchAll(
                db,
                sql: "SELECT * FROM record WHERE name IN (\(databaseQuestionMarks(count: names.count)))",
                arguments: StatementArguments(Array(names))
            )
            return Dictionary(rows.map { (Row($0).name, Row($0)) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Notes that iCloud saved the record as it was when changed at `modifiedAt`. If it changed
    /// again since, it still needs sending.
    func didUpload(_ name: String, systemFields: Data, modifiedAt: Date) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE record SET systemFields = ?, needsUpload = needsUpload AND modifiedAt <> ? WHERE name = ?",
                arguments: [systemFields, modifiedAt.timeIntervalSinceReferenceDate, name]
            )
        }
    }

    /// Notes that iCloud deleted these records, or never had them.
    func didDelete(_ names: [String]) throws {
        try queue.write { db in
            for name in names {
                try db.execute(sql: "DELETE FROM tombstone WHERE name = ?", arguments: [name])
            }
        }
    }

    /// Takes records from iCloud. Where the record changed here later than there, this one is
    /// kept and only learns iCloud's system fields, to send it again, unless iCloud's is in a
    /// later format, which this version would lose part of. A record deleted here is left out:
    /// its deletion is on its way. Returns whether anything changed.
    func receive(_ rows: [Row]) throws -> Bool {
        try queue.write { db in
            var changed = false
            for row in rows {
                if try Bool.fetchOne(db, sql: "SELECT 1 FROM tombstone WHERE name = ?", arguments: [row.name]) == true {
                    continue
                }
                if let local = try GRDB.Row.fetchOne(db, sql: "SELECT * FROM record WHERE name = ?", arguments: [row.name]).map(Row.init),
                   local.needsUpload, local.modifiedAt > row.modifiedAt, local.version >= row.version {
                    try db.execute(sql: "UPDATE record SET systemFields = ? WHERE name = ?", arguments: [row.systemFields, row.name])
                    continue
                }
                try db.execute(
                    sql: """
                        INSERT INTO record (name, type, version, modifiedAt, data, systemFields, needsUpload) VALUES (?, ?, ?, ?, ?, ?, 0)
                        ON CONFLICT(name) DO UPDATE SET type = excluded.type, version = excluded.version,
                            modifiedAt = excluded.modifiedAt, data = excluded.data, systemFields = excluded.systemFields, needsUpload = 0
                        """,
                    arguments: [row.name, row.type, row.version, row.modifiedAt.timeIntervalSinceReferenceDate, row.data, row.systemFields]
                )
                changed = true
            }
            return changed
        }
    }

    /// Deletes records iCloud deleted. One changed here since is kept, and made again in iCloud.
    /// Returns whether anything changed.
    func receiveDeletions(_ names: [String]) throws -> Bool {
        try queue.write { db in
            for name in names {
                try db.execute(sql: "UPDATE record SET systemFields = NULL WHERE name = ? AND needsUpload", arguments: [name])
                try db.execute(sql: "DELETE FROM record WHERE name = ? AND NOT needsUpload", arguments: [name])
                try db.execute(sql: "DELETE FROM tombstone WHERE name = ?", arguments: [name])
            }
            return !names.isEmpty
        }
    }

    /// Forgets the record's system fields, so it's made again in iCloud, such as after its zone
    /// was deleted.
    func forgetSystemFields(of name: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE record SET systemFields = NULL, needsUpload = 1 WHERE name = ?", arguments: [name])
        }
    }

    /// Forgets everything about syncing: the engine's state and the records' system fields. With
    /// `uploadingEverything`, every record is sent again, to start syncing afresh.
    func resetSync(uploadingEverything: Bool) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE record SET systemFields = NULL")
            if uploadingEverything {
                try db.execute(sql: "UPDATE record SET needsUpload = 1")
            }
            try Self.setSetting(.syncState, to: nil, in: db)
        }
    }
}
