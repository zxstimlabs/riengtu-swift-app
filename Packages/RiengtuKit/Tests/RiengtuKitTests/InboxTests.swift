import Foundation
import GRDB
import Testing
@testable import RiengtuKit

/// Each test gets its own folder, deleted afterwards, named like the app's, with a space.
@MainActor
final class InboxTests {
    let folder: URL
    let location: InboxStore.Location

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "InboxTests-\(UUID().uuidString)/Application Support")
        location = InboxStore.Location(
            directory: folder.appending(path: "Inbox"),
            legacyFile: InboxFile(url: folder.appending(path: "inbox.json"))
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    static let vietnam = TransactionTextTests.vietnam

    static let transfer = """
        Số tiền giao dịch: -150,000 VND
        Số dư hiện tại: 12,345,678 VND
        Thời gian: 05/11/2026 12:30:01
        Nội dung giao dịch: CHUYEN TIEN AN TRUA
        """

    /// Techcombank's notification, title then body, with the account number and name changed.
    static let notification = """
        - VND 25,000
        Tài khoản: 1234567890
        Số dư: VND 16,181,570
        NGUYEN VAN AN chuyen tien. Ma tham chieu 123456
        """

    func inbox() -> InboxStore {
        let inbox = InboxStore(location: location)
        inbox.load()
        return inbox
    }

    // MARK: Forwarding

    /// The action only forwards: reading happens in the app.
    @Test func forwardsAMessageAsItCameAndKeepsIt() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try inbox().capture(message: "  \(Self.transfer)\n", now: now) == .added)

        let item = try #require(inbox().items.first)
        #expect(item.source == .bankMessage)
        #expect(item.text == Self.transfer)
        #expect(item.date == now)
        #expect(item.amount == nil)
        #expect(!item.wasRead)
        #expect(item.isPending)
        #expect(FileManager.default.fileExists(atPath: InboxDatabase.file(in: location.directory).path(percentEncoded: false)))
    }

    @Test func leavesOutDuplicatesAndBlanks() throws {
        let inbox = inbox()
        #expect(try inbox.capture(message: "  \n ") == .empty)
        #expect(try inbox.capture(message: Self.transfer) == .added)
        #expect(try inbox.capture(message: Self.transfer + "\n") == .duplicate)
        #expect(inbox.items.count == 1)
    }

    /// Even once it's been added, so a notification sent twice isn't added twice.
    @Test func leavesOutADuplicateFromTheHistory() throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.transfer)
        try inbox.markAdded(id: inbox.items[0].id, as: UUID())
        #expect(try inbox.capture(message: Self.transfer) == .duplicate)
    }

    @Test func addsToWhatsSavedEvenBeforeLoading() throws {
        _ = try inbox().capture(message: Self.transfer)
        let later = InboxStore(location: location)
        _ = try later.capturePayment(amount: "45.000 ₫", merchant: "Phở")
        #expect(later.items.count == 2)
        #expect(later.items.first?.source == .payment)
    }

    // MARK: Payments

    @Test func capturesAPaymentNewestFirst() throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.transfer)
        #expect(try inbox.capturePayment(amount: "$4.50", merchant: " Blue  Bottle ") == .added)
        #expect(try inbox.capturePayment(amount: "0 ₫", merchant: "Nothing") == .empty)

        let first = try #require(inbox.items.first)
        #expect(first.source == .payment)
        #expect(first.amount == Decimal(string: "4.5"))
        #expect(first.currencyCode == "USD")
        #expect(first.description == "Blue Bottle")
        #expect(first.text.isEmpty)
        #expect(inbox.items.count == 2)
        #expect(self.inbox().items == inbox.items)
    }

    @Test(arguments: [nil, "", "  "])
    func capturesAPaymentWithoutItsAmount(amount: String?) throws {
        let inbox = inbox()
        #expect(try inbox.capturePayment(amount: amount, merchant: "") == .added)
        let item = try #require(inbox.items.first)
        #expect(item.amount == nil)
        #expect(item.currencyCode == nil)
        #expect(item.text.isEmpty)
    }

    /// So the person can see what Wallet passed on.
    @Test func keepsAnAmountItCantRead() throws {
        let inbox = inbox()
        #expect(try inbox.capturePayment(amount: "Pending", merchant: "Phở") == .added)
        let item = try #require(inbox.items.first)
        #expect(item.amount == nil)
        #expect(item.text == "Pending")
    }

    // MARK: Reading

    /// Without Apple Intelligence, the rules read it.
    @Test func readsNewItemsWithTheRules() async throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.notification)
        _ = try inbox.capture(message: Self.transfer)
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)

        let transfer = try #require(inbox.items.first)
        #expect(transfer.wasRead)
        #expect(transfer.amount == 150_000)
        #expect(transfer.currencyCode == "VND")
        #expect(transfer.date == TransactionTextTests.date(5, 12, 30, 1))
        #expect(transfer.description == "CHUYEN TIEN AN TRUA")
        #expect(!transfer.isMoneyIn)

        let notification = inbox.items[1]
        #expect(notification.amount == 25_000)
        #expect(notification.description == "NGUYEN VAN AN chuyen tien")
        // It doesn't say when, so it's when it arrived.
        #expect(notification.date == notification.capturedAt)
        #expect(notification.isReadyToAdd)
        #expect(self.inbox().items == inbox.items)
    }

    @Test func checksWhatTheModelAnswered() {
        let answer = TransactionReader.checked(
            summary: "  Cơm   trưa ", amount: "150,000", currency: "vnd", kind: "spending", incomeCategory: "salary"
        )
        #expect(answer == TransactionReader.Answer(description: "Cơm trưa", amount: 150_000, currencyCode: "VND", kind: .spending))
        let income = TransactionReader.checked(summary: "", amount: "0", currency: "XYZ", kind: "income", incomeCategory: "nope")
        #expect(income.amount == nil)
        #expect(income.currencyCode == nil)
        #expect(income.incomeCategory == .other)
    }

    @Test func findsTheModelsChoiceInItsAnswer() {
        let choices = ["shop", "person", "ownWallet"]
        #expect(TransactionReader.choice(in: "ownWallet", from: choices) == "ownWallet")
        #expect(TransactionReader.choice(in: "The answer is: Person.", from: choices) == "person")
        #expect(TransactionReader.choice(in: "MoMo", from: choices) == nil)
    }

    static func item(_ text: String) -> CapturedTransaction {
        CapturedTransaction(source: .bankMessage, capturedAt: .now, date: .now, amount: nil, currencyCode: nil, description: "", text: text)
    }

    @Test func takesWhatTheModelRead() {
        var item = Self.item("TK 0123 +5,000,000 VND. ND: CONG TY ABC tra luong thang 10")
        item.fill(from: TransactionReader.Answer(
            description: "tra luong thang 10", amount: 5_000_000, currencyCode: "VND", kind: .income, incomeCategory: .salary
        ), timeZone: Self.vietnam)
        #expect(item.amount == 5_000_000)
        #expect(item.isMoneyIn)
        #expect(item.incomeCategory == .salary)
        // The rules copied what "ND:" says.
        #expect(item.description == "CONG TY ABC tra luong thang 10")
    }

    /// Where the rules find no description, the model's, if it's from the message.
    @Test(arguments: [("Highlands Coffee", "Highlands Coffee"), ("Cà phê sáng", ""), ("Tài khoản", "")])
    func takesTheModelsDescriptionFromTheMessage(description: String, expected: String) {
        var item = Self.item("TK 1234567890 -45,000 VND tai HIGHLANDS COFFEE")
        item.fill(from: TransactionReader.Answer(
            description: description, amount: 45_000, currencyCode: "VND", kind: .spending
        ), timeZone: Self.vietnam)
        #expect(item.description == expected)
    }

    /// The model sometimes gives the balance.
    @Test func takesTheRulesAmountOverTheBalance() {
        var item = Self.item(Self.notification)
        item.fill(from: TransactionReader.Answer(
            description: "chuyen tien", amount: 16_181_570, currencyCode: "VND", kind: .spending
        ), timeZone: Self.vietnam)
        #expect(item.amount == 25_000)
    }

    /// Where the rules find none, the model's amount must be a number in the message: here it
    /// read "100,000" as 100.
    @Test func leavesOutAModelsAmountThatIsntInTheMessage() {
        var item = Self.item("Thong bao: TK 123456789 thay doi 100,000 luc 00:31 07/11/2026")
        item.fill(from: TransactionReader.Answer(description: "", amount: 100, currencyCode: "VND", kind: .income), timeZone: Self.vietnam)
        #expect(item.amount == nil)
        item.fill(from: TransactionReader.Answer(description: "", amount: 100_000, currencyCode: "VND", kind: .income), timeZone: Self.vietnam)
        #expect(item.amount == 100_000)
    }

    @Test func takesTheRulesAmountOverOneTheMessageDoesntGive() {
        var item = Self.item(Self.notification)
        item.fill(from: TransactionReader.Answer(
            description: "chuyen tien", amount: 250_000, currencyCode: "VND", kind: .spending
        ), timeZone: Self.vietnam)
        #expect(item.amount == 25_000)
    }

    /// Money from someone whose transfer says only their name.
    @Test func leavesTheCategoryOfANameOnlyTransferIn() {
        var item = Self.item("Tài khoản 1234567890\nSố tiền GD: + 10,000\nSố dư: 18,263,570\nNGUYEN VAN AN CHUYEN KHOAN-05112 6-14:26:22 6309ASCB02KNR93T")
        item.fill(from: TransactionReader.Answer(
            description: "", amount: 10_000, currencyCode: "VND", kind: .income, incomeCategory: .salary
        ), timeZone: Self.vietnam)
        #expect(item.isMoneyIn)
        #expect(item.description == "NGUYEN VAN AN CHUYEN KHOAN")
        #expect(item.incomeCategory == .other)
    }

    /// As Vision may read it.
    @Test func takesARefundFromTheWords() {
        var item = Self.item("Thẻ: 4 .... .... 1234\nSố tiền: + VND 51,000\nGiao dịch hoàn trà từ .OP*Green SM\n21:30")
        item.fill(from: TransactionReader.Answer(
            description: "Giao dịch hoàn trà", amount: 51_000, currencyCode: "VND", kind: .income, incomeCategory: .other
        ), timeZone: Self.vietnam)
        #expect(item.incomeCategory == .refunds)
    }

    /// A + or − says it plainly.
    @Test func takesTheSignOverTheModel() {
        var item = Self.item(Self.notification)
        item.fill(from: TransactionReader.Answer(
            description: "chuyen tien", amount: 25_000, currencyCode: "VND", kind: .income, incomeCategory: .other
        ), timeZone: Self.vietnam)
        #expect(!item.isMoneyIn)
        #expect(item.incomeCategory == nil)
    }

    @Test func takesATransferFromTheModel() {
        var item = Self.item("""
            - VND 2,042,000
            Tài khoản: 1234567890
            Số dư: VND 16,206,570
            Thanh toan no the tin dung _ So tien 2042000 VND _ Ngay 05/11/2026
            """)
        item.fill(from: TransactionReader.Answer(
            description: "Thanh toan no the tin dung", amount: 2_042_000, currencyCode: "VND", kind: .transfer
        ), timeZone: Self.vietnam)
        item.wasRead = true
        #expect(item.isTransfer)
        #expect(item.amount == 2_042_000)
        // Its two assets need choosing.
        #expect(!item.isReadyToAdd)
    }

    @Test func takesTheTimeItArrivedForADayWithoutATime() {
        let arrived = TransactionTextTests.date(5, 23, 6)
        let vietnam = Self.vietnam
        #expect(CapturedTransaction.date(TransactionTextTests.date(5, 0, 0), capturedAt: arrived, timeZone: vietnam) == arrived)
        #expect(CapturedTransaction.date(TransactionTextTests.date(4, 0, 0), capturedAt: arrived, timeZone: vietnam) == TransactionTextTests.date(4, 0, 0))
        #expect(CapturedTransaction.date(TransactionTextTests.date(5, 12, 30), capturedAt: arrived, timeZone: vietnam) == TransactionTextTests.date(5, 12, 30))
        #expect(CapturedTransaction.date(nil, capturedAt: arrived, timeZone: vietnam) == arrived)
    }

    // MARK: Screenshots

    @Test func importsWhatsOnScreenshotsOnce() throws {
        let inbox = inbox()
        let found = ScreenshotText.transactions(
            in: ScreenshotTextTests.accountHistory, takenAt: ScreenshotTextTests.takenAt, timeZone: Self.vietnam
        )
        #expect(try inbox.importScreenshots(found, timeZone: Self.vietnam) == .init(added: 3, alreadyThere: 0))
        #expect(try inbox.importScreenshots(found, timeZone: Self.vietnam) == .init(added: 0, alreadyThere: 3))
        #expect(inbox.pending.map(\.date) == found.map(\.date))
        #expect(inbox.pending.allSatisfy { $0.source == .screenshot && !$0.wasRead })
        #expect(self.inbox().pending.map(\.date) == found.map(\.date))
    }

    /// The same one on two screenshots, one with its day's heading.
    @Test func keepsTheOneWithItsDay() throws {
        let inbox = inbox()
        let text = "Tài khoản 1234567890\nSố tiền GD: - 90,000\nSố dư: 16,091,570\nNGUYEN VAN AN chuyen tien\n10:35"
        let guessed = ScreenshotText.Transaction(text: text, date: TransactionTextTests.date(5, 10, 35), isDayGuessed: true)
        let dated = ScreenshotText.Transaction(text: text, date: TransactionTextTests.date(4, 10, 35), isDayGuessed: false)
        #expect(try inbox.importScreenshots([guessed, dated], timeZone: Self.vietnam) == .init(added: 1, alreadyThere: 1))
        #expect(inbox.pending.first?.date == TransactionTextTests.date(4, 10, 35))
    }

    /// Already forwarded as a notification.
    @Test func leavesOutOneANotificationBrought() async throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.notification, now: TransactionTextTests.date(6, 8, 19, 20))
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)
        let screenshot = ScreenshotText.Transaction(
            text: "Tài khoản 1234567890\nSố tiền GD: - 25,000\nSố dư: 16,181,570\nNGUYEN VAN AN chuyen tien\n08:19",
            date: TransactionTextTests.date(6, 8, 19), isDayGuessed: false
        )
        #expect(try inbox.importScreenshots([screenshot], timeZone: Self.vietnam) == .init(added: 0, alreadyThere: 1))
    }

    /// Dated by its heading and time, not when it was imported.
    @Test func readsAScreenshotsTransactionOnItsDay() async throws {
        let inbox = inbox()
        let found = ScreenshotText.transactions(
            in: ScreenshotTextTests.accountHistory, takenAt: ScreenshotTextTests.takenAt, timeZone: Self.vietnam
        )
        _ = try inbox.importScreenshots(found, timeZone: Self.vietnam)
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)
        let card = try #require(inbox.pending.last)
        #expect(card.amount == 2_042_000)
        #expect(card.date == TransactionTextTests.date(5, 23, 6))
        #expect(card.description == "Thanh toan no the tin dung")
    }

    // MARK: Two messages for the same money

    /// From ACB to Techcombank, with the account numbers and name changed.
    static let fromACB = """
        Thong bao thay doi so du tai khoan
        ACB: TK 123456789(VND) - 100,000 luc 00:31 07/11/2026. So du 69,272,331. GD: NGUYEN VAN AN CHUYEN KHOAN-071126-00:31:28 6311ASCB02V2Q9YC
        """
    static let intoTechcombank = """
        + VND 100,000
        Tài khoản: 1234567890
        Số dư: VND 16,191,570
        NGUYEN VAN AN CHUYEN KHOAN-07112 6-00:31:28 6311ASCB02V2Q9YC
        """

    static func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = vietnam
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute, second: second))!
    }

    func readAndJoin(_ messages: [(String, Date)]) async throws -> InboxStore {
        let inbox = inbox()
        for (message, date) in messages { _ = try inbox.capture(message: message, now: date) }
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)
        try inbox.joinPairs(now: Self.at(1, 0))
        return inbox
    }

    /// It nets to zero, so both are left out.
    @Test func leavesOutBothSidesOfATransferBetweenOwnAccounts() async throws {
        let inbox = try await readAndJoin([(Self.fromACB, Self.at(0, 31, 30)), (Self.intoTechcombank, Self.at(0, 31, 35))])
        #expect(inbox.pending.isEmpty)
        let sides = inbox.history
        #expect(Set(sides.map(\.text)) == [Self.fromACB, Self.intoTechcombank])
        let out = try #require(sides.first { !$0.isMoneyIn })
        let into = try #require(sides.first { $0.isMoneyIn })
        #expect(out.amount == 100_000)
        #expect(out.pairedID == into.id)
        #expect(into.pairedID == out.id)
        #expect(sides.allSatisfy { inbox.isOwnTransferSide($0) && $0.entryID == nil })
        #expect(self.inbox().pending.isEmpty)
    }

    /// Money that came into an account and went straight out of it again was passed on.
    @Test func doesntJoinMoneyPassedOnFromTheSameAccount() async throws {
        let inbox = try await readAndJoin([
            ("+ VND 100,000\nTài khoản: 1234567890\nSố dư: VND 200,000\nTRAN THI BINH chuyen tien", Self.at(9, 0)),
            ("- VND 100,000\nTài khoản: 1234567890\nSố dư: VND 100,000\nNGUYEN VAN AN chuyen tien", Self.at(9, 2)),
        ])
        #expect(inbox.pending.count == 2)
        #expect(inbox.pending.allSatisfy { !$0.isTransfer && $0.pairedID == nil })
    }

    @Test func joinsSidesFarApartOnlyWithTheSameCode() async throws {
        let apart = try await readAndJoin([
            ("TK 123456789 - 100,000 VND luc 09:00 07/11/2026. ND: chuyen tien", Self.at(9, 0)),
            ("+ VND 100,000\nTài khoản: 1234567890\nSố dư: VND 300,000\nchuyen tien", Self.at(9, 20)),
        ])
        #expect(apart.pending.count == 2)
        try FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        let withCode = try await readAndJoin([(Self.fromACB, Self.at(0, 31, 30)), (Self.intoTechcombank, Self.at(0, 51))])
        #expect(withCode.pending.isEmpty)
    }

    /// A payment from Wallet, and the bank's message about it.
    @Test func leavesOutATransactionThatCameTwice() async throws {
        let inbox = inbox()
        _ = try inbox.capturePayment(amount: "45.000 ₫", merchant: "Highlands Coffee", now: Self.at(8, 0, 0))
        _ = try inbox.capture(message: "- VND 45,000\nTài khoản: 1234567890\nSố dư: VND 1,955,000\nHIGHLANDS COFFEE", now: Self.at(8, 0, 40))
        await inbox.readNewItems(usingModel: false, timeZone: Self.vietnam)
        #expect(try inbox.joinPairs(now: Self.at(9, 0)) == 1)
        let kept = try #require(inbox.pending.first)
        #expect(inbox.pending.count == 1)
        #expect(kept.source == .bankMessage)
        #expect(!kept.isTransfer)
        #expect(inbox.history.first?.source == .payment)
        #expect(inbox.history.first.map(inbox.isOwnTransferSide) == false)
    }

    @Test func putsBothSidesBackInTheInbox() async throws {
        let inbox = try await readAndJoin([(Self.fromACB, Self.at(0, 31, 30)), (Self.intoTechcombank, Self.at(0, 31, 35))])
        let side = try #require(inbox.history.first)
        try inbox.split(id: side.id)
        #expect(inbox.pending.count == 2)
        #expect(inbox.pending.allSatisfy { !$0.isTransfer && $0.pairedID == nil && $0.isPending })
        #expect(inbox.history.isEmpty)
    }

    // MARK: History

    @Test func keepsWhatWasAddedOrDismissedInTheHistory() throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.transfer)
        _ = try inbox.capture(message: Self.notification)
        let entryID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try inbox.markAdded(id: inbox.items[1].id, as: entryID, now: now)
        try inbox.dismiss(id: inbox.items[0].id, now: now.addingTimeInterval(60))

        let reopened = self.inbox()
        #expect(reopened.pending.isEmpty)
        #expect(reopened.history.map(\.text) == [Self.notification, Self.transfer])
        #expect(reopened.item(forEntry: entryID)?.text == Self.transfer)
        #expect(reopened.history.first?.handledAt == now.addingTimeInterval(60))
    }

    @Test func deletesTheHistoryAfterItsTime() throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.transfer)
        _ = try inbox.capture(message: Self.notification)
        _ = try inbox.capture(message: "Waiting")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try inbox.dismiss(id: inbox.items[2].id, now: now.addingTimeInterval(-8 * 86_400))
        try inbox.dismiss(id: inbox.items[1].id, now: now.addingTimeInterval(-86_400))

        try inbox.deleteHistory(handledBefore: now.addingTimeInterval(-7 * 86_400))
        #expect(inbox.items.map(\.text) == ["Waiting", Self.notification])
        #expect(self.inbox().items == inbox.items)

        try inbox.deleteHistory()
        #expect(inbox.items.map(\.text) == ["Waiting"])
    }

    @Test func removesItems() throws {
        let inbox = inbox()
        _ = try inbox.capture(message: Self.transfer)
        _ = try inbox.capturePayment(amount: "45.000 ₫", merchant: "Phở")
        try inbox.remove(id: inbox.items[0].id)
        #expect(inbox.items.count == 1)

        try inbox.removeAll()
        #expect(inbox.items.isEmpty)
        #expect(self.inbox().items.isEmpty)
    }

    // MARK: Storage

    /// Builds 8 and earlier kept the inbox in a JSON file.
    @Test func movesTheFileEarlierBuildsKeptIntoTheDatabase() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let item = CapturedTransaction(
            source: .payment, capturedAt: date, date: date, amount: 45_000, currencyCode: "VND", description: "Phở"
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let seconds = date.timeIntervalSinceReferenceDate
        try Data(#"""
            {"version": 1, "items": [{"id": "\#(item.id.uuidString)", "source": "payment", "capturedAt": \#(seconds),
             "date": \#(seconds), "amount": "45000", "currency": "VND", "description": "Phở"}]}
            """#.utf8).write(to: location.legacyFile!.url)

        let inbox = inbox()
        #expect(inbox.items == [item])
        #expect(!FileManager.default.fileExists(atPath: location.legacyFile!.url.path(percentEncoded: false)))
        #expect(self.inbox().items == [item])
    }

    @Test func startsEmptyFromADamagedDatabase() throws {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4_096).write(to: InboxDatabase.file(in: location.directory))
        let inbox = inbox()
        #expect(inbox.items.isEmpty)
        #expect(try inbox.capture(message: Self.transfer) == .added)
    }

    /// One from a later version is left alone, not read.
    @Test func skipsARowItCantRead() throws {
        let database = try InboxDatabase()
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO item (id, source, capturedAt, date) VALUES (?, 'smoke signal', 0, 0)", arguments: [UUID().uuidString])
        }
        #expect(try database.items().isEmpty)
    }

    @Test func refusesAFileFromALaterVersion() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "items": []}"#.utf8).write(to: location.legacyFile!.url)
        #expect(throws: InboxFile.LoadError.newerVersion(99)) { try self.location.legacyFile!.load() }
    }
}
