import Foundation
import Testing
@testable import RiengtuKit

/// Each test gets its own folder, deleted afterwards.
final class LedgerStoreTests {
    let folder: URL
    let file: LedgerFile

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "LedgerStoreTests-\(UUID().uuidString)")
        file = LedgerFile(url: folder.appending(path: "ledger.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static func expense(_ amount: Decimal = 45_000) -> Expense {
        Expense(amount: amount, currencyCode: "VND", category: .food, date: .now, note: "Phở")
    }

    @Test func startsEmptyWithoutAFile() throws {
        let store = LedgerStore(file: file)
        #expect(store.status == .notLoaded)
        store.load()
        #expect(store.status == .ready)
        #expect(store.ledger == Ledger())
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))
    }

    @Test func savesEveryChange() throws {
        let store = LedgerStore(file: file)
        store.load()
        let kept = Self.expense()
        let deleted = Self.expense(30_000)
        try store.save(kept)
        try store.save(deleted)
        try store.deleteExpense(id: deleted.id)

        let reopened = LedgerStore(file: file)
        reopened.load()
        #expect(reopened.ledger.expenses == [kept])
        #expect(reopened.ledger.recentCurrencyCodes == ["VND"])
    }

    @Test func refusesChangesBeforeLoading() {
        let store = LedgerStore(file: file)
        #expect(throws: LedgerStore.NotReadyError.self) { try store.save(Self.expense()) }
    }

    @Test func keepsTheLedgerAsItWasWhenSavingFails() throws {
        // A file where the folder should be, so the folder can't be made.
        try Data().write(to: folder)
        let store = LedgerStore(file: file)
        store.load()

        #expect(throws: (any Error).self) { try store.save(Self.expense()) }
        #expect(store.ledger.expenses.isEmpty)
    }

    @Test(arguments: [
        #"not json"#,
        #"{"version": 1, "expenses": [{"id": "nope"}], "recentCurrencyCodes": []}"#,
        #"{"version": 99, "expenses": [], "recentCurrencyCodes": []}"#,
    ])
    func leavesAnUnreadableFileAlone(contents: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file.url)
        let store = LedgerStore(file: file)
        store.load()

        #expect(store.status == .unreadable)
        #expect(throws: LedgerStore.NotReadyError.self) { try store.save(Self.expense()) }
        #expect(try String(contentsOf: file.url, encoding: .utf8) == contents)
    }

    @Test func startsOverKeepingTheUnreadableFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        let store = LedgerStore(file: file)
        store.load()

        try store.startOver()
        try store.save(Self.expense())

        #expect(store.status == .ready)
        #expect(store.ledger.expenses.count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path())
        #expect(names.contains { $0.hasPrefix("ledger-unreadable-") })
    }

    @Test func erasesEverything() throws {
        let store = LedgerStore(file: file)
        store.load()
        try store.save(Self.expense())
        try store.eraseAll()

        #expect(store.ledger == Ledger())
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))
    }
}
