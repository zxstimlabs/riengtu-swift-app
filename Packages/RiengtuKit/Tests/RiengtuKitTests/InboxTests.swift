import Foundation
import Testing
@testable import RiengtuKit

/// Each test gets its own folder, deleted afterwards.
@MainActor
final class InboxTests {
    let folder: URL
    let file: InboxFile

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "InboxTests-\(UUID().uuidString)")
        file = InboxFile(url: folder.appending(path: "inbox.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static let transfer = """
        Số tiền giao dịch: -150,000 VND
        Số dư hiện tại: 12,345,678 VND
        Thời gian: 05/11/2026 12:30:01
        Nội dung giao dịch: CHUYEN TIEN AN TRUA
        """

    @Test func capturesABankMessageAndKeepsItOnDisk() throws {
        let inbox = InboxStore(file: file)
        #expect(try inbox.capture(message: Self.transfer, timeZone: TransactionTextTests.vietnam) == .added)

        let reopened = InboxStore(file: file)
        reopened.load()
        let item = try #require(reopened.items.first)
        #expect(item.source == .bankMessage)
        #expect(item.amount == 150_000)
        #expect(item.currencyCode == "VND")
        #expect(item.date == TransactionTextTests.date(5, 12, 30, 1))
        #expect(item.description == "CHUYEN TIEN AN TRUA")
        #expect(item.text == Self.transfer)
        #expect(!item.wasRead)
    }

    @Test func leavesOutDuplicatesAndBlanks() throws {
        let inbox = InboxStore(file: file)
        #expect(try inbox.capture(message: "  \n ") == .empty)
        #expect(try inbox.capture(message: Self.transfer) == .added)
        #expect(try inbox.capture(message: Self.transfer + "\n") == .duplicate)
        #expect(inbox.items.count == 1)
        #expect(inbox.items.first?.isMoneyIn == false)
    }

    @Test func capturesMoneyReceivedAndKeepsItOnDisk() throws {
        let inbox = InboxStore(file: file)
        #expect(try inbox.capture(message: "TK 0123 +5.000.000 VND. ND: Luong") == .added)

        let reopened = InboxStore(file: file)
        reopened.load()
        let item = try #require(reopened.items.first)
        #expect(item.isMoneyIn)
        #expect(item.amount == 5_000_000)
        #expect(item.description == "Luong")
    }

    @Test func keepsAMessageWithoutAnAmountForThePersonToFinish() throws {
        let inbox = InboxStore(file: file)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try inbox.capture(message: "Quý khách vừa chuyển khoản thành công. ND: Tien nha", now: now) == .added)
        #expect(inbox.items.first?.amount == nil)
        #expect(inbox.items.first?.date == now)
        #expect(inbox.items.first?.description == "Tien nha")
    }

    @Test func capturesAPaymentNewestFirst() throws {
        let inbox = InboxStore(file: file)
        _ = try inbox.capture(message: Self.transfer)
        #expect(try inbox.capturePayment(amount: Decimal(string: "4.5")!, currencyCode: "USD", merchant: " Blue  Bottle ") == .added)
        #expect(try inbox.capturePayment(amount: 0, currencyCode: "USD", merchant: "Nothing") == .empty)

        let first = try #require(inbox.items.first)
        #expect(first.source == .payment)
        #expect(first.description == "Blue Bottle")
        #expect(inbox.items.count == 2)
    }

    @Test func capturesAPaymentWithoutItsAmount() throws {
        let inbox = InboxStore(file: file)
        #expect(try inbox.capturePayment(amount: nil, currencyCode: "VND", merchant: "") == .added)
        let item = try #require(inbox.items.first)
        #expect(item.amount == nil)
        #expect(item.currencyCode == nil)
    }

    @Test func removesItems() throws {
        let inbox = InboxStore(file: file)
        _ = try inbox.capture(message: Self.transfer)
        _ = try inbox.capturePayment(amount: 45_000, currencyCode: "VND", merchant: "Phở")
        try inbox.remove(id: inbox.items[0].id)
        #expect(inbox.items.count == 1)

        try inbox.removeAll()
        #expect(inbox.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
    }

    @Test func addsToWhatsOnDiskEvenBeforeLoading() throws {
        _ = try InboxStore(file: file).capture(message: Self.transfer)
        let later = InboxStore(file: file)
        _ = try later.capturePayment(amount: 45_000, currencyCode: "VND", merchant: "Phở")
        #expect(later.items.count == 2)
    }

    @Test func startsEmptyFromADamagedFile() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file.url)
        let inbox = InboxStore(file: file)
        inbox.load()
        #expect(inbox.items.isEmpty)
        #expect(try inbox.capture(message: Self.transfer) == .added)
    }

    @Test func refusesAFileFromALaterVersion() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "items": []}"#.utf8).write(to: file.url)
        #expect(throws: InboxFile.LoadError.newerVersion(99)) { try self.file.load() }
    }

    @Test func checksWhatTheModelRead() {
        let reading = TransactionReader.reading(description: "  Cơm   trưa ", amount: "150,000", currency: "vnd")
        #expect(reading == TransactionText.Reading(amount: 150_000, currencyCode: "VND", description: "Cơm trưa"))
        #expect(TransactionReader.reading(description: "", amount: "0", currency: "XYZ").amount == nil)
        #expect(TransactionReader.reading(description: "", amount: nil, currency: "XYZ").currencyCode == nil)
    }
}
