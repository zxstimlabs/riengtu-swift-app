import Foundation
import GRDB
import Testing
@testable import RiengtuKit

/// Each test gets its own folder, deleted afterwards, named like the app's, with a space.
@MainActor
final class LedgerStoreTests {
    let folder: URL
    let location: LedgerStore.Location

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "LedgerStoreTests-\(UUID().uuidString)/Application Support")
        location = LedgerStore.Location(
            directory: folder.appending(path: "Ledger"),
            legacyFile: LedgerFile(url: folder.appending(path: "ledger.json"))
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    static func expense(_ amount: Decimal = 45_000) -> Entry {
        Entry(kind: .expense(.food, account: nil), amount: amount, currencyCode: "VND", date: .now, note: "Phở")
    }

    func store() -> LedgerStore {
        let store = LedgerStore(location: location)
        store.load()
        return store
    }

    func writeLegacyFile(_ contents: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: location.legacyFile!.url)
    }

    @Test func startsEmpty() throws {
        let store = LedgerStore(location: location)
        #expect(store.status == .notLoaded)
        store.load()
        #expect(store.status == .ready)
        #expect(store.ledger == Ledger())
        #expect(FileManager.default.fileExists(atPath: LedgerDatabase.file(in: location.directory).path(percentEncoded: false)))
    }

    @Test func savesEveryChange() throws {
        let store = store()
        let kept = Self.expense()
        let deleted = Self.expense(30_000)
        try store.save(kept)
        try store.save(deleted)
        try store.deleteEntry(id: deleted.id)
        try store.addStarterTags()
        try store.renameTag("Work", to: "Công việc")
        let asset = Asset(kind: .stock, name: "FPT", currencyCode: "VND", value: .holding(quantity: 100, price: 125_500), valuedAt: .now)
        try store.save(asset)

        let reopened = self.store()
        #expect(reopened.ledger == store.ledger)
        #expect(reopened.ledger.entries == [kept])
        #expect(reopened.ledger.assets == [asset])
        #expect(reopened.ledger.recentCurrencyCodes == ["VND"])
        #expect(reopened.ledger.tags == ["Personal", "Family", "Công việc", "Gift", "Trip"])
        #expect(!reopened.ledger.needsStarterTags)
    }

    @Test func keepsDeletingTheStarterTags() throws {
        let store = store()
        try store.addStarterTags()
        for tag in Tags.starter {
            try store.deleteTag(tag)
        }
        #expect(!self.store().ledger.needsStarterTags)
    }

    /// A file from before the database moves into it, and is deleted.
    @Test func movesTheFileEarlierBuildsKeptIntoTheDatabase() throws {
        try writeLegacyFile(#"""
            {"version": 4, "recentCurrencyCodes": ["VND"], "tags": ["Work"], "expenses": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
             "amount": "45000", "currency": "VND", "category": "drinks", "date": 0, "tags": ["Work"]}],
             "assets": [{"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "kind": "cash", "currency": "VND", "amount": "500000", "valuedAt": 0}]}
            """#)
        let store = store()

        #expect(store.status == .ready)
        let entry = try #require(store.ledger.entries.first)
        #expect(entry.kind == .expense(.drinks, account: nil))
        #expect(entry.tags == ["Work"])
        #expect(store.ledger.tags == ["Work"])
        #expect(store.ledger.assets.first?.worth == 500_000)
        #expect(!FileManager.default.fileExists(atPath: location.legacyFile!.url.path(percentEncoded: false)))
        #expect(self.store().ledger == store.ledger)
    }

    /// A version 5 file's balances included what its entries changed, so they don't count twice.
    @Test func keepsTheBalancesOfAVersion5File() throws {
        try writeLegacyFile(#"""
            {"version": 5, "recentCurrencyCodes": ["VND"], "entries": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "type": "expense",
             "amount": "45000", "currency": "VND", "category": "food", "account": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "date": 0}],
             "assets": [{"id": "7F9619FF-8B86-D011-B42D-00C04FC964FF", "kind": "cash", "currency": "VND", "amount": "455000", "valuedAt": 0}]}
            """#)
        let store = store()
        let cash = try #require(store.ledger.assets.first)
        #expect(store.ledger.current(cash).worth == 455_000)
    }

    @Test(arguments: [
        #"not json"#,
        #"{"version": 1, "expenses": [{"id": "nope"}], "recentCurrencyCodes": []}"#,
        #"{"version": 99, "expenses": [], "recentCurrencyCodes": []}"#,
    ])
    func leavesAFileItCantReadAlone(contents: String) throws {
        try writeLegacyFile(contents)
        let store = store()

        #expect(store.status == .unreadable)
        #expect(throws: LedgerStore.NotReadyError.self) { try store.save(Self.expense()) }
        #expect(try String(contentsOf: location.legacyFile!.url, encoding: .utf8) == contents)
    }

    @Test func startsOverKeepingAFileItCantRead() throws {
        try writeLegacyFile("not json")
        let store = store()
        try store.startOver()
        try store.save(Self.expense())

        #expect(store.status == .ready)
        #expect(store.ledger.entries.count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("ledger-unreadable-") })
    }

    @Test func startsOverKeepingADamagedDatabase() throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4_096).write(to: LedgerDatabase.file(in: location.directory))
        let store = store()
        #expect(store.status == .unreadable)

        try store.startOver()
        try store.save(Self.expense())
        #expect(store.status == .ready)
        let names = try FileManager.default.contentsOfDirectory(atPath: location.directory.path(percentEncoded: false))
        #expect(names.contains { $0.hasPrefix("ledger-unreadable-") })
    }

    @Test func refusesChangesBeforeLoading() {
        let store = LedgerStore(location: location)
        #expect(throws: LedgerStore.NotReadyError.self) { try store.save(Self.expense()) }
    }

    @Test func keepsTheLedgerAsItWasWhenSavingFails() throws {
        let database = try LedgerDatabase()
        try database.queue.write { db in
            try db.execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON record BEGIN SELECT RAISE(ABORT, 'refused'); END")
        }
        let store = try LedgerStore(database: database)

        #expect(throws: (any Error).self) { try store.save(Self.expense()) }
        #expect(store.ledger.entries.isEmpty)
    }

    @Test func showsButDoesntChangeWhatALaterVersionSaved() throws {
        let database = try LedgerDatabase()
        let entry = Self.expense()
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO record (name, type, version, modifiedAt, data) VALUES (?, 'Entry', 2, 0, ?)",
                arguments: [LedgerDatabase.name(ofEntry: entry.id), try JSONEncoder().encode(entry)]
            )
        }
        let store = try LedgerStore(database: database)

        #expect(store.ledger.entries == [entry])
        #expect(store.ledger.newerIDs == [entry.id])
        #expect(throws: LedgerStore.NewerVersionError.self) { try store.save(entry) }
        try store.deleteEntry(id: entry.id)
        #expect(store.ledger.entries.isEmpty)
    }

    @Test func tellsSyncWhatChanged() throws {
        let store = try LedgerStore(database: LedgerDatabase())
        var changes: [([String], [String])] = []
        store.didChangeRecords = { changes.append(($0, $1)) }

        let entry = Self.expense()
        try store.save(entry)
        try store.deleteEntry(id: entry.id)
        // Nothing changed.
        try store.deleteEntry(id: entry.id)

        let name = LedgerDatabase.name(ofEntry: entry.id)
        #expect(changes.map(\.0) == [[name], []])
        #expect(changes.map(\.1) == [[], [name]])
    }

    @Test func erasesEverything() throws {
        let store = store()
        try store.save(Self.expense())
        try store.addStarterTags()
        try store.eraseAll()

        #expect(store.ledger == Ledger())
        #expect(self.store().ledger == Ledger())
    }
}
