import Foundation
import Testing
@testable import RiengtuKit

/// Transactions added before a rule existed, brought up to date when the person asks.
@MainActor
struct PastTransactionsTests {
    static func income(_ note: String, party: String = "") -> Entry {
        Entry(kind: .income(.other, account: nil), amount: 10_000, currencyCode: "VND", date: Date(timeIntervalSinceReferenceDate: 0),
              note: note, party: party)
    }

    @Test func movesTheNameFromTheNote() throws {
        let entry = Self.income("NGUYEN VAN AN chuyen tien")
        let updated = try #require(PastTransactions.updates(in: Ledger(entries: [entry]), messages: { _ in nil }).first)
        #expect(updated.id == entry.id)
        #expect(updated.party == "NGUYEN VAN AN")
        #expect(updated.note == "chuyen tien")
    }

    /// The model left the name out of the note, but the bank's message in the history has it.
    @Test func findsTheNameInTheMessage() throws {
        let entry = Self.income("chuyển tiền")
        let message = "+ VND 10,000\nTài khoản: 1234567890\nSố dư: VND 16,251,570\nPHAM THI THU LAN chuyen tien"
        let updated = try #require(PastTransactions.updates(in: Ledger(entries: [entry]), messages: { $0 == entry.id ? message : nil }).first)
        #expect(updated.party == "PHAM THI THU LAN")
        #expect(updated.note == "chuyển tiền")
    }

    @Test func leavesWhatsFilledInOrHasNoName() {
        let entries = [
            Self.income("NGUYEN VAN AN chuyen tien", party: "Anh An"),
            Self.income("Ăn trưa với đồng nghiệp"),
            Entry(kind: .transfer(from: nil, to: nil), amount: 10_000, currencyCode: "VND", date: .now, note: "NGUYEN VAN AN chuyen tien"),
        ]
        #expect(PastTransactions.updates(in: Ledger(entries: entries), messages: { _ in nil }).isEmpty)
    }

    @Test func leavesWhatALaterVersionSaved() {
        var ledger = Ledger(entries: [Self.income("NGUYEN VAN AN chuyen tien")])
        ledger.newerIDs = [ledger.entries[0].id]
        #expect(PastTransactions.updates(in: ledger, messages: { _ in nil }).isEmpty)
    }

    @Test func savesThemAtOnce() throws {
        let entries = [Self.income("NGUYEN VAN AN chuyen tien"), Self.income("TRAN THI BINH chuyen khoan")]
        let store = LedgerStore(inMemory: Ledger(entries: entries))
        try store.save(PastTransactions.updates(in: store.ledger, messages: { _ in nil }))
        #expect(Set(store.ledger.entries.map(\.party)) == ["NGUYEN VAN AN", "TRAN THI BINH"])
        #expect(PastTransactions.updates(in: store.ledger, messages: { _ in nil }).isEmpty)
    }

    /// What waits in the inbox is read again, with how it's read now.
    @Test func readsTheInboxAgain() async throws {
        let inbox = InboxStore(inMemory: [])
        _ = try inbox.capture(message: InboxTests.notification)
        await inbox.readNewItems(usingModel: false, timeZone: InboxTests.vietnam)
        #expect(inbox.unreadCount == 0)
        #expect(try inbox.readAllAgain() == 1)
        #expect(inbox.unreadCount == 1)
        await inbox.readNewItems(usingModel: false, timeZone: InboxTests.vietnam)
        let item = try #require(inbox.pending.first)
        #expect(item.wasRead && item.party == "NGUYEN VAN AN")
    }
}
