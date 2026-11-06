import CloudKit
import Foundation
import GRDB
import Testing
@testable import RiengtuKit

/// The database's records, and how it keeps them in step with iCloud.
struct LedgerDatabaseTests {
    static let entry = Entry(kind: .expense(.food, account: nil), amount: 45_000, currencyCode: "VND", date: LedgerTests.date(5), note: "Phở")
    static var name: String { LedgerDatabase.name(ofEntry: entry.id) }

    static func row(_ entry: Entry, version: Int = 1, modifiedAt: Date, systemFields: Data? = nil) throws -> LedgerDatabase.Row {
        LedgerDatabase.Row(
            name: LedgerDatabase.name(ofEntry: entry.id), type: "Entry", version: version,
            modifiedAt: modifiedAt, data: try JSONEncoder().encode(entry), systemFields: systemFields
        )
    }

    static func save(_ ledger: Ledger, to database: LedgerDatabase, from old: Ledger = Ledger(), at date: Date = .now) throws {
        try database.write(LedgerDatabase.Changes(from: old, to: ledger, now: date))
    }

    // MARK: Records

    @Test func keepsEachRecordAsJSONWithItsVersion() throws {
        let database = try LedgerDatabase()
        try Self.save(Ledger(entries: [Self.entry]), to: database)

        let row = try #require(try database.rows(named: [Self.name])[Self.name])
        #expect(row.type == "Entry")
        #expect(row.version == 1)
        #expect(try JSONDecoder().decode(Entry.self, from: row.data) == Self.entry)
        #expect(row.needsUpload)
    }

    @Test func givesATagOneRecordWhateverItsSpelling() {
        #expect(LedgerDatabase.name(ofTag: "Đà Lạt trip") == LedgerDatabase.name(ofTag: "  đà lạt TRIP "))
        #expect(LedgerDatabase.name(ofTag: "Tết") != LedgerDatabase.name(ofTag: "Tet"))
        #expect(LedgerDatabase.name(ofTag: "Tết").allSatisfy { $0.isASCII })
    }

    @Test func keepsTheOrderOfTagsAndOfEntriesOnTheSameDate() throws {
        let database = try LedgerDatabase()
        var ledger = Ledger(tags: ["Work", "Trip"])
        let first = Self.entry
        var second = Self.entry
        second.id = UUID()
        ledger.save(first)
        ledger.save(second)
        try Self.save(ledger, to: database)
        let renamed = { var renamed = ledger; renamed.renameTag("Work", to: "Job"); return renamed }()
        try Self.save(renamed, to: database, from: ledger)

        let loaded = try database.load()
        #expect(loaded.entries.map(\.id) == [second.id, first.id])
        #expect(loaded.tags == ["Job", "Trip"])
    }

    @Test func keepsWhatItCantReadAsItIs() throws {
        let database = try LedgerDatabase()
        try database.queue.write { db in
            // A kind of record a later version added, and a kind of entry this one doesn't know.
            try db.execute(sql: "INSERT INTO record (name, type, version, modifiedAt, data) VALUES ('budget.1', 'Budget', 1, 0, X'7B7D')")
            try db.execute(sql: #"INSERT INTO record (name, type, version, modifiedAt, data) VALUES ('entry.2', 'Entry', 2, 0, CAST('{"type": "loan"}' AS BLOB))"#)
        }
        let ledger = try database.load()
        #expect(ledger.unreadableRecordCount == 2)
        #expect(ledger.entries.isEmpty)

        try Self.save(Ledger(entries: [Self.entry]), to: database, from: ledger)
        #expect(try database.rows(named: ["budget.1", "entry.2"]).count == 2)
    }

    // MARK: Sync

    @Test func marksChangesToSendUntilICloudHasThem() throws {
        let database = try LedgerDatabase()
        let sent = Date(timeIntervalSinceReferenceDate: 100)
        try Self.save(Ledger(entries: [Self.entry]), to: database, at: sent)
        #expect(try database.pendingChanges().saved == [Self.name])

        // Changed again after it was sent: it still needs sending.
        var changed = Self.entry
        changed.amount = 50_000
        try Self.save(Ledger(entries: [changed]), to: database, from: Ledger(entries: [Self.entry]), at: sent + 1)
        try database.didUpload(Self.name, systemFields: Data([1]), modifiedAt: sent)
        #expect(try database.pendingChanges().saved == [Self.name])

        try database.didUpload(Self.name, systemFields: Data([2]), modifiedAt: sent + 1)
        #expect(try database.pendingChanges().saved.isEmpty)
        #expect(try database.rows(named: [Self.name])[Self.name]?.systemFields == Data([2]))
    }

    @Test func marksDeletionsUntilICloudDeletesThem() throws {
        let database = try LedgerDatabase()
        let ledger = Ledger(entries: [Self.entry])
        try Self.save(ledger, to: database)
        try Self.save(Ledger(), to: database, from: ledger)
        #expect(try database.pendingChanges().deleted == [Self.name])
        #expect(try database.pendingChanges().saved.isEmpty)

        try database.didDelete([Self.name])
        #expect(try database.pendingChanges().deleted.isEmpty)
    }

    @Test func takesALaterChangeFromICloud() throws {
        let database = try LedgerDatabase()
        try Self.save(Ledger(entries: [Self.entry]), to: database, at: Date(timeIntervalSinceReferenceDate: 100))
        var theirs = Self.entry
        theirs.note = "Bún chả"

        #expect(try database.receive([Self.row(theirs, modifiedAt: Date(timeIntervalSinceReferenceDate: 200), systemFields: Data([9]))]))

        #expect(try database.load().entries == [theirs])
        let row = try #require(try database.rows(named: [Self.name])[Self.name])
        #expect(!row.needsUpload)
        #expect(row.systemFields == Data([9]))
    }

    @Test func keepsALaterChangeMadeHere() throws {
        let database = try LedgerDatabase()
        try Self.save(Ledger(entries: [Self.entry]), to: database, at: Date(timeIntervalSinceReferenceDate: 200))
        var theirs = Self.entry
        theirs.note = "Bún chả"

        #expect(try database.receive([Self.row(theirs, modifiedAt: Date(timeIntervalSinceReferenceDate: 100), systemFields: Data([9]))]) == false)

        #expect(try database.load().entries == [Self.entry])
        let row = try #require(try database.rows(named: [Self.name])[Self.name])
        // Sent again, over iCloud's.
        #expect(row.needsUpload)
        #expect(row.systemFields == Data([9]))
    }

    @Test func neverKeepsAnOlderFormatOverALaterOne() throws {
        let database = try LedgerDatabase()
        try Self.save(Ledger(entries: [Self.entry]), to: database, at: Date(timeIntervalSinceReferenceDate: 200))

        #expect(try database.receive([Self.row(Self.entry, version: 2, modifiedAt: Date(timeIntervalSinceReferenceDate: 100))]))

        let ledger = try database.load()
        #expect(ledger.newerIDs == [Self.entry.id])
        #expect(try database.pendingChanges().saved.isEmpty)
    }

    @Test func leavesOutARecordDeletedHere() throws {
        let database = try LedgerDatabase()
        let ledger = Ledger(entries: [Self.entry])
        try Self.save(ledger, to: database)
        try Self.save(Ledger(), to: database, from: ledger)

        #expect(try database.receive([Self.row(Self.entry, modifiedAt: .distantFuture)]) == false)
        #expect(try database.load().entries.isEmpty)
    }

    @Test func deletesWhatICloudDeletedUnlessItChangedHere() throws {
        let database = try LedgerDatabase()
        var other = Self.entry
        other.id = UUID()
        try #require(try database.receive([
            Self.row(Self.entry, modifiedAt: .distantPast, systemFields: Data([1])),
            Self.row(other, modifiedAt: .distantPast, systemFields: Data([1])),
        ]))
        // Changed here since.
        var changed = other
        changed.amount = 1
        try Self.save(Ledger(entries: [Self.entry, changed]), to: database, from: Ledger(entries: [Self.entry, other]))

        _ = try database.receiveDeletions([Self.name, LedgerDatabase.name(ofEntry: other.id)])

        #expect(try database.load().entries == [changed])
        let kept = try #require(try database.rows(named: [LedgerDatabase.name(ofEntry: other.id)]).first?.value)
        #expect(kept.systemFields == nil)
        #expect(kept.needsUpload)
    }

    @Test func startsSyncingAfresh() throws {
        let database = try LedgerDatabase()
        _ = try database.receive([Self.row(Self.entry, modifiedAt: .distantPast, systemFields: Data([1]))])
        try database.setSyncState(Data([1, 2, 3]))

        try database.resetSync(uploadingEverything: true)

        #expect(try database.syncState() == nil)
        #expect(try database.pendingChanges().saved == [Self.name])
        #expect(try database.rows(named: [Self.name])[Self.name]?.systemFields == nil)
    }

    @Test func erasesEverything() throws {
        let database = try LedgerDatabase()
        var ledger = Ledger(entries: [Self.entry])
        ledger.addStarterTags()
        try Self.save(ledger, to: database)
        try database.setSyncState(Data([1]))
        try database.eraseAll()

        #expect(try database.load() == Ledger())
        #expect(try database.pendingChanges() == ([], []))
        #expect(try database.syncState() == nil)
    }
}

/// How records become CloudKit records and back.
struct CloudRecordTests {
    static func row(name: String = "entry.1", type: String = "Entry", systemFields: Data? = nil) -> LedgerDatabase.Row {
        LedgerDatabase.Row(
            name: name, type: type, version: 3, modifiedAt: Date(timeIntervalSinceReferenceDate: 123.5),
            data: Data(#"{"amount": "45000"}"#.utf8), systemFields: systemFields
        )
    }

    @Test func roundTripsARecordWithItsDataEncrypted() throws {
        let record = CloudRecord.make(from: Self.row())
        #expect(record.recordType == "Entry")
        #expect(record.recordID == CloudRecord.recordID("entry.1"))
        #expect(record.encryptedValues[CloudRecord.Field.data] as? Data == Self.row().data)
        #expect(record[CloudRecord.Field.data] == nil)

        var row = try #require(CloudRecord.row(from: record))
        #expect(row.systemFields != nil)
        row.systemFields = nil
        #expect(row == Self.row())
    }

    @Test func buildsOnTheSystemFieldsICloudSent() throws {
        let sent = CloudRecord.make(from: Self.row(name: "tag.1", type: "Tag"))
        let record = CloudRecord.make(from: Self.row(name: "tag.1", type: "Tag", systemFields: CloudRecord.systemFields(of: sent)))
        #expect(record.recordID == sent.recordID)
        #expect(record.recordType == "Tag")
    }

    @Test func leavesOutRecordsThatArentTheLedgers() {
        let elsewhere = CKRecord(recordType: "Entry", recordID: CKRecord.ID(recordName: "entry.1", zoneID: CKRecordZone.ID(zoneName: "Other")))
        elsewhere[CloudRecord.Field.version] = 1
        elsewhere.encryptedValues[CloudRecord.Field.data] = Data()
        #expect(CloudRecord.row(from: elsewhere) == nil)

        let empty = CKRecord(recordType: "Entry", recordID: CloudRecord.recordID("entry.2"))
        #expect(CloudRecord.row(from: empty) == nil)
    }
}
