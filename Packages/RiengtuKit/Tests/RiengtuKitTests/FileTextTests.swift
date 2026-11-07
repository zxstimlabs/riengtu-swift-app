import Foundation
import Testing
@testable import RiengtuKit

/// Made-up files in the shapes banks and apps export, with made-up accounts and names.
@MainActor
struct FileTextTests {
    static let vietnam = TransactionTextTests.vietnam

    static let statement = """
        Ngày giao dịch,Nội dung,Ghi nợ,Ghi có,Số dư
        03/11/2026,"Thanh toan tien dien, thang 10",1504246,,18475880
        04/11/2026,NGUYEN VAN AN chuyen tien,33000,,18442880
        04/11/2026,NGUYEN VAN AN chuyen tien,33000,,18409880
        05/11/2026,CONG TY ABC tra luong,,15000000,33409880
        """

    @Test func readsAStatementARowEach() throws {
        let messages = FileText.messages(in: Data(Self.statement.utf8), fileExtension: "csv")
        #expect(messages.count == 4)
        #expect(messages[0] == "Ngày giao dịch: 03/11/2026\nNội dung: Thanh toan tien dien, thang 10\nGhi nợ: 1504246\nSố dư: 18475880")

        let bill = TransactionText.read(messages[0], timeZone: Self.vietnam)
        #expect(bill.amount == 1_504_246)
        #expect(bill.direction == .moneyOut)
        #expect(bill.date == TransactionTextTests.date(3, 0, 0))
        #expect(bill.description == "Thanh toan tien dien, thang 10")
        let pay = TransactionText.read(messages[3], timeZone: Self.vietnam)
        #expect(pay.amount == 15_000_000)
        #expect(pay.direction == .moneyIn)
    }

    @Test func readsSemicolonsAndTabs() {
        #expect(FileText.messages(in: Data("Date;Amount;Note\n05/11/2026;-45000;Pho".utf8), fileExtension: "csv")
            == ["Date: 05/11/2026\nAmount: -45000\nNote: Pho"])
        #expect(FileText.messages(in: Data("Date\tAmount\n05/11/2026\t-45000".utf8), fileExtension: "tsv")
            == ["Date: 05/11/2026\nAmount: -45000"])
    }

    @Test func readsAJSONExportAnObjectEach() throws {
        let json = """
            {"version": 2, "account": {"name": "Vi"}, "transactions": [
              {"date": "2026-11-05", "amount": -45000, "note": "Phở", "pending": false},
              {"date": "2026-11-06", "amount": 200000, "note": "Tra tien cafe", "meta": {"currency": "VND"}}
            ]}
            """
        let messages = FileText.messages(in: Data(json.utf8), fileExtension: "json")
        #expect(messages == [
            "amount: -45000\ndate: 2026-11-05\nnote: Phở",
            "amount: 200000\ndate: 2026-11-06\nmeta.currency: VND\nnote: Tra tien cafe",
        ])
        let first = TransactionText.read(messages[0], timeZone: Self.vietnam)
        #expect(first.amount == 45_000)
        #expect(first.direction == .moneyOut)
    }

    @Test func readsTextAParagraphOrALineEach() {
        let paragraphs = "TK 123456789 -45,000 VND luc 08:00 05/11/2026. ND: Pho\n\nTK 123456789 +200,000 VND luc 09:00 05/11/2026. ND: Luong"
        #expect(FileText.messages(in: Data(paragraphs.utf8), fileExtension: "txt").count == 2)
        let lines = "05/11 -45,000 VND Pho\n05/11 -65,000 VND Highlands\n06/11 +200,000 VND Luong"
        #expect(FileText.messages(in: Data(lines.utf8), fileExtension: "txt").count == 3)
        #expect(FileText.messages(in: Data("Just a note, no money".utf8), fileExtension: "txt").isEmpty)
    }

    @Test func importsAFilesRowsOnce() async throws {
        let inbox = InboxStore(inMemory: [])
        let messages = FileText.messages(in: Data(Self.statement.utf8), fileExtension: "csv")
        let now = TransactionTextTests.date(7, 9, 0)
        #expect(try inbox.importFile(messages, now: now, timeZone: Self.vietnam) == .init(added: 4, alreadyThere: 0))
        #expect(try inbox.importFile(messages, now: now, timeZone: Self.vietnam) == .init(added: 0, alreadyThere: 4))
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)
        // Both 33,000 the same day: two transactions, not one twice.
        #expect(inbox.pending.filter { $0.amount == 33_000 }.count == 2)
        #expect(inbox.pending.map(\.date).contains(TransactionTextTests.date(3, 0, 0)))
        #expect(inbox.pending.allSatisfy { $0.source == .file && $0.wasRead })
    }
}
