import Foundation
import Observation
import os

/// The money in and out waiting to be added to the ledger, and the history of what was added or
/// dismissed, newest first, saved to the inbox's database (`InboxDatabase`) with every change.
///
/// The Shortcuts actions only forward: a bank's notification or email goes in as it came, and is
/// read in the app (`readNewItems()`), by Apple Intelligence where it's available. Once added or
/// dismissed, an item stays in the history with its message, so the person can check what was
/// read from it, until the app deletes the history after the time the person chose.
///
/// On the main actor, because the app and its Shortcuts actions share one store: an action can
/// run while the app is open.
@MainActor
@Observable
public final class InboxStore {
    public enum CaptureResult: Equatable, Sendable {
        case added
        /// The same message is already in the inbox or its history.
        case duplicate
        /// There was nothing in the message.
        case empty
    }

    /// Where the inbox's database is, and the file builds before it kept the inbox in.
    public struct Location: Sendable {
        public var directory: URL
        public var legacyFile: InboxFile?

        public init(directory: URL, legacyFile: InboxFile?) {
            self.directory = directory
            self.legacyFile = legacyFile
        }

        /// The `Inbox` folder in the app's Application Support folder.
        public static var applicationSupport: Location {
            Location(directory: .applicationSupportDirectory.appending(path: "Inbox"), legacyFile: .applicationSupport)
        }
    }

    /// Everything in the inbox and its history, newest first.
    public private(set) var items: [CapturedTransaction] = []
    /// Whether new items are being read.
    public private(set) var isReading = false
    /// The item being read now.
    public private(set) var readingItemID: CapturedTransaction.ID?
    /// How many have been read since reading started, and when it started, for how long is left.
    public private(set) var readCount = 0
    public private(set) var readingStartedAt: Date?
    /// Whether reading stopped because the model can't read now, such as when iOS limits it for
    /// an app in the background, or didn't answer in time (`modelDidNotAnswer`). It goes on next
    /// time it starts.
    public private(set) var isWaitingForModel = false
    /// Whether the model didn't answer in time (`ExpenseTagger.timeLimit`), which the person can
    /// try again, or read the rest without it.
    public private(set) var modelDidNotAnswer = false
    /// Whether the person stopped reading (`stop()`), which they can start again.
    public private(set) var wasStopped = false

    @ObservationIgnored private var readingTask: Task<Void, Never>?
    @ObservationIgnored private var readingID: UUID?
    /// The item the person asked to read again, which is read next, as a transaction.
    @ObservationIgnored private var readAgainID: CapturedTransaction.ID?

    @ObservationIgnored private let location: Location?
    /// Opened when it's first needed, since it can't be before the device's first unlock.
    @ObservationIgnored private var database: InboxDatabase?

    private static let logger = Logger(subsystem: "vn.riengtu", category: "InboxStore")

    /// The longest message kept: enough for any notice, without a long email's footer.
    static let maximumTextLength = 5_000

    public init(location: Location) {
        self.location = location
    }

    /// A store with a database in memory, for previews and tests.
    public init(inMemory items: [CapturedTransaction] = []) {
        location = nil
        // An in-memory database can't fail to open.
        let database = try! InboxDatabase()
        try! database.save(items)
        self.database = database
        self.items = (try? database.items()) ?? []
    }

    /// What waits to be added or dismissed, the latest transaction first.
    public var pending: [CapturedTransaction] {
        items.filter(\.isPending).sorted { $0.date > $1.date }
    }

    /// How many wait to be read.
    public var unreadCount: Int {
        items.count { $0.isPending && !$0.wasRead }
    }

    /// What was added or dismissed, most recently first.
    public var history: [CapturedTransaction] {
        items.filter { !$0.isPending }.sorted { $0.handledAt! > $1.handledAt! }
    }

    /// The item an entry was added from, while it's in the history.
    public func item(forEntry id: Entry.ID) -> CapturedTransaction? {
        items.first { $0.entryID == id }
    }

    /// Reads the database again, since Shortcuts may have added to it. If it can't be opened now,
    /// the next call tries again.
    public func load() {
        do {
            try loadIfNeeded()
            if let database { items = try database.items() }
        } catch {
            Self.logger.error("Can't read the inbox yet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts a bank's notification, email or message in the inbox as it came, to be read in the
    /// app. Only forwards, so the action is quick, and works while the device is locked.
    public func capture(message text: String, now: Date = .now) throws -> CaptureResult {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
        guard !text.isEmpty else { return .empty }
        try loadIfNeeded()
        if items.contains(where: { $0.source == .bankMessage && $0.text == text }) { return .duplicate }
        let item = CapturedTransaction(
            source: .bankMessage, capturedAt: now, date: now, amount: nil, currencyCode: nil, description: "", text: text
        )
        try insert(item)
        return .added
    }

    /// Puts a card payment, such as one from Apple Pay, in the inbox. `amount` is the text the
    /// automation passes on, such as Wallet's "45.000 ₫" (`TransactionText.amount`). Without an
    /// amount, as when Wallet doesn't pass one on, it's still added, and the amount is typed in
    /// when it's added to the ledger. Text that isn't an amount is kept for the person to see.
    public func capturePayment(amount text: String?, merchant: String, now: Date = .now) throws -> CaptureResult {
        let text = String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumAmountTextLength))
        let amount = TransactionText.amount(text)
        // Such as a transit card's tap.
        if let amount, amount.value <= 0 { return .empty }
        try loadIfNeeded()
        let item = CapturedTransaction(
            source: .payment,
            capturedAt: now,
            date: now,
            amount: amount?.value,
            currencyCode: amount?.currencyCode,
            description: Tags.tidy(merchant),
            text: amount == nil ? text : ""
        )
        try insert(item)
        return .added
    }

    static let maximumAmountTextLength = 100

    public struct ImportResult: Equatable, Sendable {
        public var added: Int
        /// Already in the inbox or its history, from another screenshot or a notification.
        public var alreadyThere: Int

        public init(added: Int, alreadyThere: Int) {
            self.added = added
            self.alreadyThere = alreadyThere
        }
    }

    /// Puts the transactions in files the person picked in the inbox (`FileText`), to be read as
    /// forwarded messages are. One already there, with the same text, is left out; a file's rows
    /// can't be told apart from a notification's otherwise, since a file often gives only the day.
    public func importFile(_ messages: [String], now: Date = .now, timeZone: TimeZone = .current) throws -> ImportResult {
        try loadIfNeeded()
        var added: [CapturedTransaction] = []
        for message in messages {
            let text = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
            guard !text.isEmpty, !(items + added).contains(where: { $0.text == text }) else { continue }
            let date = TransactionText.read(text, timeZone: timeZone).date ?? now
            added.append(CapturedTransaction(
                source: .file, capturedAt: now, date: date, amount: nil, currencyCode: nil, description: "", text: text
            ))
        }
        try database?.save(added.sorted { $0.date < $1.date })
        items = added.sorted { $0.date > $1.date } + items
        return ImportResult(added: added.count, alreadyThere: messages.count - added.count)
    }

    /// Puts transactions found on screenshots in the inbox, to be read as forwarded messages
    /// are. One that's already there, or in the history, is left out: the same transaction on
    /// another screenshot, or a notification for it.
    public func importScreenshots(
        _ transactions: [ScreenshotText.Transaction], now: Date = .now, timeZone: TimeZone = .current
    ) throws -> ImportResult {
        try loadIfNeeded()
        // Ones dated by a heading first, so they're kept over the same ones with a guessed day.
        let ordered = transactions.filter { !$0.isDayGuessed } + transactions.filter(\.isDayGuessed)
        var added: [CapturedTransaction] = []
        for transaction in ordered {
            let item = CapturedTransaction(
                source: .screenshot, capturedAt: now, date: transaction.date, amount: nil, currencyCode: nil,
                description: "", text: String(transaction.text.prefix(Self.maximumTextLength))
            )
            guard !(items + added).contains(where: { $0.isSameTransaction(as: item, timeZone: timeZone) }) else { continue }
            added.append(item)
        }
        // Saved oldest first, so the newest comes first when they're loaded again.
        try database?.save(added.sorted { $0.date < $1.date })
        items = added.sorted { $0.date > $1.date } + items
        return ImportResult(added: added.count, alreadyThere: transactions.count - added.count)
    }

    /// Moves an item to the history once it's been added to the ledger as `entryID`.
    public func markAdded(id: CapturedTransaction.ID, as entryID: Entry.ID, now: Date = .now) throws {
        try update(id: id) {
            $0.handledAt = now
            $0.entryID = entryID
        }
    }

    /// Moves an item to the history without adding it.
    public func dismiss(id: CapturedTransaction.ID, now: Date = .now) throws {
        try update(id: id) { $0.handledAt = now }
    }

    /// Deletes an item, from the inbox or its history.
    public func remove(id: CapturedTransaction.ID) throws {
        try loadIfNeeded()
        try database?.delete(ids: [id])
        items.removeAll { $0.id == id }
    }

    /// Deletes what was added or dismissed before `date`, or everything in the history when
    /// it's `nil`. What waits in the inbox stays.
    public func deleteHistory(handledBefore date: Date? = nil) throws {
        try loadIfNeeded()
        guard let database else { return }
        try database.deleteHistory(handledBefore: date)
        items = try database.items()
    }

    /// Empties the inbox and its history.
    public func removeAll() throws {
        try loadIfNeeded()
        try database?.deleteAll()
        items = []
    }

    /// Starts reading what's new, unless it's reading already. It goes on until nothing new is
    /// left, including what arrives meanwhile. With Apple Intelligence where it's available,
    /// unless the person chose to read without it (`usingModel`), when it didn't answer.
    public func startReading(usingModel: Bool = true) {
        guard readingTask == nil else { return }
        let id = UUID()
        readingID = id
        isReading = true
        isWaitingForModel = false
        modelDidNotAnswer = false
        wasStopped = false
        readCount = 0
        readingStartedAt = .now
        readingTask = Task {
            await readNewItems(usingModel: usingModel && ExpenseTagger.availability == .available)
            // Then the whole inbox, together.
            try? joinPairs()
            // Unless it was stopped, and maybe started again, meanwhile.
            guard readingID == id else { return }
            readingTask = nil
            isReading = false
        }
    }

    /// Looks at everything read that waits in the inbox together, once each has been read on its
    /// own, for two messages about the same money, and keeps one:
    ///
    /// - The two sides of a transfer between the person's own accounts: money out of one account,
    ///   and the same amount into another, within 10 minutes, or 30 when both carry the same
    ///   reference code. It nets to zero, so by the user's choice both are left out, to the
    ///   history. Not when both name the same account, as when money is passed on.
    /// - A transaction that came twice, such as a payment from Wallet and the bank's message about
    ///   it: the same amount the same way within 2 minutes, from different sources or with the
    ///   same balance. The fuller message is kept.
    ///
    /// What's left out moves to the history, joined to the other (`pairedID`), where the person
    /// can put it back (`split`). Returns how many pairs.
    @discardableResult
    public func joinPairs(now: Date = .now) throws -> Int {
        try loadIfNeeded()
        var candidates = pending.filter { $0.wasRead && $0.amount != nil && $0.pairedID == nil }
            .sorted { $0.date < $1.date }
        var joined = 0
        func same(_ a: CapturedTransaction, _ b: CapturedTransaction) -> Bool {
            a.amount == b.amount && (a.currencyCode ?? "VND") == (b.currencyCode ?? "VND")
        }
        func seconds(_ a: CapturedTransaction, _ b: CapturedTransaction) -> TimeInterval {
            abs(a.date.timeIntervalSince(b.date))
        }
        func join(keeping kept: CapturedTransaction, hiding other: CapturedTransaction, asTransfer: Bool) throws {
            try update(id: kept.id) {
                $0.pairedID = other.id
                if asTransfer {
                    $0.isTransfer = true
                    $0.handledAt = now
                }
            }
            try update(id: other.id) {
                $0.pairedID = kept.id
                $0.handledAt = now
            }
            candidates.removeAll { $0.id == kept.id || $0.id == other.id }
            joined += 1
        }

        // Transfers between the person's own accounts.
        for out in candidates where !out.isMoneyIn {
            guard candidates.contains(where: { $0.id == out.id }) else { continue }
            let outCodes = TransactionText.codes(in: out.text)
            let outAccounts = TransactionText.accounts(in: out.text)
            let match = candidates
                .filter { item in
                    guard item.isMoneyIn, same(out, item) else { return false }
                    let accounts = TransactionText.accounts(in: item.text)
                    if !accounts.isEmpty, !outAccounts.isDisjoint(with: accounts) { return false }
                    let sharesCode = !outCodes.isDisjoint(with: TransactionText.codes(in: item.text))
                    return seconds(out, item) <= (sharesCode ? 1_800 : 600)
                }
                .min { seconds(out, $0) < seconds(out, $1) }
            if let match { try join(keeping: out, hiding: match, asTransfer: true) }
        }

        // A transaction that came twice.
        for item in candidates {
            guard candidates.contains(where: { $0.id == item.id }) else { continue }
            let balances = TransactionText.balances(in: item.text)
            let match = candidates.first { other in
                guard other.id != item.id, other.isMoneyIn == item.isMoneyIn, same(item, other), seconds(item, other) <= 120
                else { return false }
                let otherBalances = TransactionText.balances(in: other.text)
                return other.source != item.source || (!balances.isEmpty && !balances.isDisjoint(with: otherBalances))
            }
            guard let match else { continue }
            // The bank's message over a payment, or the longer one.
            let keepsItem = item.source != .payment && (match.source == .payment || item.text.count >= match.text.count)
            try join(keeping: keepsItem ? item : match, hiding: keepsItem ? match : item, asTransfer: false)
        }
        return joined
    }

    /// Puts an item that was dismissed or left out back in the inbox, with the other message it
    /// was joined to. Not one that was added, which would add it twice.
    public func putBack(id: CapturedTransaction.ID) throws {
        try loadIfNeeded()
        guard let item = items.first(where: { $0.id == id }), item.entryID == nil else { return }
        if item.pairedID != nil {
            try split(id: id)
        } else {
            try update(id: id) {
                $0.handledAt = nil
                $0.isNotTransaction = false
            }
        }
    }

    /// Whether an item was left out as one side of a transfer between the person's own accounts.
    public func isOwnTransferSide(_ item: CapturedTransaction) -> Bool {
        guard let otherID = item.pairedID, let other = items.first(where: { $0.id == otherID }) else { return false }
        return item.isMoneyIn != other.isMoneyIn
    }

    /// Undoes a join, from either message: they're two transactions, each waiting in the inbox
    /// again, and a transfer's sides are expense and income again.
    public func split(id: CapturedTransaction.ID) throws {
        try loadIfNeeded()
        guard let item = items.first(where: { $0.id == id }), let otherID = item.pairedID else { return }
        let wasTransfer = isOwnTransferSide(item)
        for id in [id, otherID] {
            try update(id: id) {
                $0.pairedID = nil
                $0.handledAt = nil
                if wasTransfer { $0.isTransfer = false }
            }
        }
    }

    /// Reads an item again, before anything else, with what the person added to help (`hint`),
    /// such as what it was for, or the amount: one that's being read, or waits, or that Apple
    /// Intelligence didn't answer for, or that was read without an amount. It's read as a
    /// transaction, since the person asked, and can dismiss it otherwise. What's being read now
    /// stops, and is read after. The caller starts reading.
    public func readAgain(id: CapturedTransaction.ID, hint: String) throws {
        try update(id: id) { item in
            item.hint = String(hint.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TransactionReader.maximumHintLength))
            item.wasRead = false
            item.isNotTransaction = false
            // What reading fills in, from scratch.
            item.party = ""
            item.isTransfer = false
            item.expenseCategory = nil
            item.incomeCategory = nil
        }
        readAgainID = id
        stopReading()
    }

    /// Marks everything read that waits in the inbox to be read again, with how it's read now,
    /// when the person asks (Settings > Read Inbox Again), such as after reading has improved.
    /// What the person added to help (`hint`) stays. Not what's in the history, which was added or
    /// dismissed. Returns how many; the caller starts reading.
    @discardableResult
    public func readAllAgain() throws -> Int {
        try loadIfNeeded()
        let ids = pending.filter(\.wasRead).map(\.id)
        for id in ids {
            try update(id: id) { item in
                item.wasRead = false
                item.isTransfer = false
                item.expenseCategory = nil
                item.incomeCategory = nil
                item.party = ""
            }
        }
        if !ids.isEmpty { stopReading() }
        return ids.count
    }

    /// Stops reading because the person asked, such as when it seems stuck. What wasn't read
    /// waits for them to start again, with Apple Intelligence or without.
    public func stop() {
        stopReading()
        wasStopped = true
    }

    /// Stops reading, such as when the app goes to the background. What wasn't read yet is read
    /// next time.
    public func stopReading() {
        readingTask?.cancel()
        readingTask = nil
        readingID = nil
        readingItemID = nil
        isReading = false
    }

    /// Reads what's new in the inbox, one item at a time, saving each. A bank's message that
    /// isn't about money that moved, such as an ad or a one-time code, goes to the history
    /// (`isNotTransaction`): Apple Intelligence tells, where the rules can't plainly.
    /// With Apple Intelligence (`usingModel`), the model reads each message: the amount, what
    /// kind it is, where income came from, and what for; then it picks an expense's category.
    /// The rules (`TransactionText`) check the model's amount, and read the message on their own
    /// where the model isn't available or can't answer. Where it can't answer now, or doesn't
    /// answer in time, reading stops, and the rest wait for it.
    func readNewItems(
        usingModel: Bool = ExpenseTagger.availability == .available, timeZone: TimeZone = .current, now: Date = .now
    ) async {
        // Not once it's stopped, when another reading may have started.
        defer { if !Task.isCancelled { readingItemID = nil } }
        // The one the person asked to read again, then the oldest, as they'd add them.
        while let item = pending.first(where: { $0.id == readAgainID && !$0.wasRead }) ?? pending.last(where: { !$0.wasRead }) {
            let isAskedFor = item.id == readAgainID
            if isAskedFor { readAgainID = nil }
            readingItemID = item.id
            var read = item
            do {
                // Not one the person asked to read again, or added to: they'd dismiss an ad.
                if item.source == .bankMessage, !isAskedFor, item.hint.isEmpty,
                   try await !Self.isTransaction(item.text, usingModel: usingModel) {
                    read.isNotTransaction = true
                    read.handledAt = now
                } else {
                    try await Self.read(&read, usingModel: usingModel, timeZone: timeZone)
                }
            } catch is CancellationError {
                // Read next time, still first.
                if isAskedFor, readAgainID == nil { readAgainID = item.id }
                return
            } catch {
                if isAskedFor { readAgainID = item.id }
                // It stays unread, for when the model can read it, though where it didn't
                // answer in time, the person may choose to read it without the model.
                isWaitingForModel = true
                modelDidNotAnswer = error is TimedOutError
                return
            }
            guard !Task.isCancelled else { return }
            read.wasRead = true
            // The person may have added or dismissed it meanwhile.
            guard items.contains(where: { $0.id == item.id && $0.isPending }) else { continue }
            do {
                try update(id: item.id) { $0 = read }
            } catch {
                return
            }
            readCount += 1
        }
    }

    /// Whether a bank's message tells of money that moved, rather than being an ad, an offer, a
    /// one-time code or a reminder: where it's plain, as the rules tell, and otherwise as Apple
    /// Intelligence does, or where it can't, as their words suggest.
    private static func isTransaction(_ text: String, usingModel: Bool) async throws -> Bool {
        if let isTransaction = TransactionText.isTransaction(text) { return isTransaction }
        if usingModel, let isTransaction = try await TransactionReader.isTransaction(text) { return isTransaction }
        return !TransactionText.looksLikeOtherMessage(text)
    }

    /// Reads an item's message, and picks an expense's category. Throws only where the model
    /// can't answer now or in time (`waitsForModel`), or reading was stopped.
    private static func read(_ item: inout CapturedTransaction, usingModel: Bool, timeZone: TimeZone) async throws {
        if item.source != .payment {
            var answer: TransactionReader.Answer?
            if usingModel {
                do {
                    answer = try await TransactionReader.read(item.text, hint: item.hint)
                } catch where waitsForModel(error) {
                    throw error
                } catch {
                    // Such as a language the model doesn't support. The rules read it.
                }
            }
            item.fill(from: answer, timeZone: timeZone)
        }
        // Not for a payment whose description is only the sender's name, which the model
        // would guess a category for.
        if usingModel, !item.isMoneyIn, !item.isTransfer, !item.description.isEmpty,
           !TransactionText.isDefaultTransferContent(item.description) {
            do {
                // With what the person added, which may say what it was for.
                let note = item.hint.isEmpty ? item.description : item.description + "\n" + item.hint
                item.expenseCategory = try await ExpenseTagger.suggest(
                    note: note, amount: item.amount, currencyCode: item.currencyCode ?? "VND", tags: []
                ).category
            } catch where waitsForModel(error) {
                throw error
            } catch {
                // No category, so it's "other".
            }
        }
    }

    /// Whether reading stops for an error, rather than the rules reading what the model didn't:
    /// it was stopped, or the model can't answer now (`TransactionReader.TryLaterError`) or in
    /// time (`TimedOutError`).
    private static func waitsForModel(_ error: any Error) -> Bool {
        error is CancellationError || error is TransactionReader.TryLaterError || error is TimedOutError
            || TransactionReader.isTemporary(error)
    }

    /// Opens the database the first time it's needed, moving in the file builds before it kept
    /// the inbox in. A damaged database is deleted and the inbox starts empty: nothing in it is in
    /// the ledger yet.
    private func loadIfNeeded() throws {
        guard database == nil, let location else { return }
        let database: InboxDatabase
        do {
            database = try InboxDatabase(directory: location.directory)
        } catch where LedgerDatabase.isDamaged(error) {
            Self.logger.error("The inbox's database is damaged. Starting an empty inbox.")
            try FileManager.default.removeItem(at: InboxDatabase.file(in: location.directory))
            database = try InboxDatabase(directory: location.directory)
        }
        if let legacy = location.legacyFile {
            do {
                try database.save(try legacy.load())
                try legacy.delete()
            } catch is DecodingError {
                Self.logger.error("The inbox file is damaged. Leaving it out.")
                try legacy.delete()
            } catch InboxFile.LoadError.newerVersion {
                // From a later build, which has a database too. Left as it is.
            }
        }
        items = try database.items()
        self.database = database
    }

    private func insert(_ item: CapturedTransaction) throws {
        try database?.save([item])
        items.insert(item, at: 0)
    }

    private func update(id: CapturedTransaction.ID, _ change: (inout CapturedTransaction) -> Void) throws {
        try loadIfNeeded()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        change(&item)
        do {
            try database?.save([item])
        } catch {
            Self.logger.error("Can't save the inbox: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        items[index] = item
    }
}

extension CapturedTransaction {
    /// Whether two are the same transaction. On two screenshots, the same one has the same time
    /// and amounts, the balance among them, whatever day was guessed for it; otherwise, the same
    /// amount within two minutes, such as a screenshot of one a notification was forwarded for.
    func isSameTransaction(as other: CapturedTransaction, timeZone: TimeZone) -> Bool {
        // A file's rows often give only the day, so two the same that day are two.
        if source == .file || other.source == .file { return text == other.text }
        if source == .screenshot, other.source == .screenshot {
            if text == other.text { return true }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let time = calendar.dateComponents([.hour, .minute], from: date)
            return time == calendar.dateComponents([.hour, .minute], from: other.date)
                && TransactionText.amounts(in: text).map(\.value) == TransactionText.amounts(in: other.text).map(\.value)
        }
        guard let amount = amount ?? TransactionText.read(text, timeZone: timeZone).amount,
              amount == other.amount ?? TransactionText.read(other.text, timeZone: timeZone).amount
        else { return false }
        return abs(date.timeIntervalSince(other.date)) <= 120
    }

    /// When the money moved: what the message says, or when it arrived. A message that gives
    /// only the day, such as "Ngay 05/11/2026", is read as midnight, so on the day it arrived,
    /// the time it arrived is closer.
    static func date(_ read: Date?, capturedAt: Date, timeZone: TimeZone) -> Date {
        guard let read else { return capturedAt }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if read == calendar.startOfDay(for: read), calendar.isDate(read, inSameDayAs: capturedAt) {
            return capturedAt
        }
        return read
    }

    /// Who sent the money or got it, a person or a company (`TransactionText.party`), apart
    /// from what it was for: the model leaves names out of its description, as it's asked to,
    /// and the rules' description starts with the name, as banks write "NGUYEN VAN AN chuyen
    /// tien", which leaves "chuyen tien".
    mutating func findParty() {
        guard let name = TransactionText.party(in: text) else { return }
        party = name
        description = TransactionText.removingParty(name, from: description)
    }

    /// Fills in what a bank's message says, from what Apple Intelligence read (`answer`), checked
    /// with the rules, or from the rules alone without it.
    ///
    /// The model sometimes gives the balance as the amount, so its amount is used only if it's
    /// one the message gives and not the balance; otherwise the rules' is. A + or − in front of
    /// the amount says plainly which way it went, over the kind the model read.
    mutating func fill(from answer: TransactionReader.Answer?, timeZone: TimeZone) {
        let rules = TransactionText.read(text, timeZone: timeZone)
        let amounts = TransactionText.amounts(in: text)
        // A screenshot's or a file's transaction is dated by what it says, not when it was imported.
        date = Self.date(rules.date, capturedAt: source == .screenshot || source == .file ? date : capturedAt, timeZone: timeZone)
        guard let answer else {
            amount = rules.amount
            currencyCode = rules.currencyCode
            isMoneyIn = rules.direction == .moneyIn
            description = rules.description
            findParty()
            return
        }

        let moved = amounts.filter { !$0.isBalance }
        // Where the rules found no amount, the model's must still be a number in the message,
        // unless the person gave it in what they added (`hint`).
        if let value = answer.amount,
           TransactionText.numbers(in: hint).contains(value)
            || !amounts.contains(where: { $0.isBalance && $0.value == value })
            && (moved.isEmpty ? TransactionText.numbers(in: text).contains(value) : moved.contains(where: { $0.value == value })) {
            amount = value
            currencyCode = moved.first { $0.value == value }?.currencyCode ?? answer.currencyCode ?? rules.currencyCode
        } else {
            amount = rules.amount
            currencyCode = rules.currencyCode
        }
        if let signed = amounts.first(where: { $0.isSigned && $0.value == amount }) {
            isMoneyIn = signed.direction == .moneyIn
        } else {
            switch answer.kind {
            case .income: isMoneyIn = true
            case .spending: isMoneyIn = false
            case .transfer: isMoneyIn = rules.direction == .moneyIn
            }
        }
        isTransfer = answer.kind == .transfer
        // The rules copy the words a label such as "Nội dung" gives, as the model is asked to,
        // and the model sometimes gives other words, or makes some up. So its description is
        // used where no label gives one, and only if it's from the message; it's tidier than the
        // whole line the rules take after the balance.
        if let labeled = TransactionText.labeledDescription(in: text).map(TransactionText.clean), !labeled.isEmpty {
            description = labeled
        } else if TransactionText.isWritten(answer.description, in: text) || TransactionText.isWritten(answer.description, in: hint) {
            description = answer.description
        } else {
            description = rules.description
        }
        findParty()
        // A refund says so plainly, and money from someone whose transfer says only their name
        // doesn't say what it was for.
        if !isMoneyIn || isTransfer {
            incomeCategory = nil
        } else if TransactionText.isRefund(text) {
            incomeCategory = .refunds
        } else if TransactionText.isDefaultTransferContent(description) {
            incomeCategory = .other
        } else {
            incomeCategory = answer.incomeCategory ?? .other
        }
    }
}
