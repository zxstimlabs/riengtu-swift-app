import Foundation
import Observation
import os

/// The payments waiting to be added as expenses, newest first, saved to their own file after
/// every change.
///
/// On the main actor, because the app and its Shortcuts actions share one store: an action can
/// run while the app is open.
@MainActor
@Observable
public final class InboxStore {
    public enum CaptureResult: Equatable, Sendable {
        case added
        /// Money came in, which isn't an expense.
        case moneyIn
        /// The same message is already in the inbox.
        case duplicate
        /// There was nothing in the message.
        case empty
    }

    public private(set) var items: [CapturedTransaction]

    @ObservationIgnored private let file: InboxFile?
    @ObservationIgnored private var isLoaded: Bool

    private static let logger = Logger(subsystem: "vn.riengtu", category: "InboxStore")

    /// The longest message kept: enough for any notice, without a long email's footer.
    static let maximumTextLength = 5_000

    public init(file: InboxFile) {
        self.file = file
        items = []
        isLoaded = false
    }

    /// A store that keeps `items` in memory and saves nothing, for previews and tests.
    public init(inMemory items: [CapturedTransaction] = []) {
        file = nil
        self.items = items
        isLoaded = true
    }

    /// Reads the file again, since Shortcuts may have added to it. If it can't be read now, the
    /// next call tries again. If it's damaged, it's set aside and the inbox starts empty: nothing
    /// in it is an expense yet.
    public func load() {
        guard let file else { return }
        do {
            items = try file.load()
            isLoaded = true
        } catch is DecodingError {
            Self.logger.error("The inbox file is damaged. Starting an empty inbox.")
            try? FileManager.default.removeItem(at: file.url)
            items = []
            isLoaded = true
        } catch {
            Self.logger.error("Can't read the inbox file yet: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts the transaction a bank's message describes in the inbox, unless money came in.
    public func capture(message text: String, now: Date = .now, timeZone: TimeZone = .current) throws -> CaptureResult {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
        guard !text.isEmpty else { return .empty }
        let reading = TransactionText.read(text, timeZone: timeZone)
        if reading.direction == .moneyIn { return .moneyIn }

        try loadIfNeeded()
        if items.contains(where: { $0.text == text }) { return .duplicate }
        let item = CapturedTransaction(
            source: .bankMessage,
            capturedAt: now,
            date: reading.date ?? now,
            amount: reading.amount,
            currencyCode: reading.currencyCode,
            description: reading.description,
            text: text
        )
        try commit { $0.insert(item, at: 0) }
        return .added
    }

    /// Puts a payment whose amount is known, such as one from Apple Pay, in the inbox.
    public func capturePayment(amount: Decimal, currencyCode: String, merchant: String, now: Date = .now) throws -> CaptureResult {
        guard amount > 0 else { return .empty }
        try loadIfNeeded()
        let item = CapturedTransaction(
            source: .payment,
            capturedAt: now,
            date: now,
            amount: amount,
            currencyCode: currencyCode,
            description: Tags.tidy(merchant)
        )
        try commit { $0.insert(item, at: 0) }
        return .added
    }

    public func remove(id: CapturedTransaction.ID) throws {
        try loadIfNeeded()
        try commit { $0.removeAll { $0.id == id } }
    }

    /// Empties the inbox, and deletes its file.
    public func removeAll() throws {
        try file?.delete()
        items = []
        isLoaded = true
    }

    /// Reads new bank messages with Apple Intelligence, for a cleaner description and any amount
    /// the rules missed. Each is read once, while the app is open.
    public func readNewMessages() async {
        guard ExpenseTagger.availability == .available else { return }
        let unread = items.filter { $0.source == .bankMessage && !$0.wasRead && !$0.text.isEmpty }
        for item in unread {
            let reading: TransactionText.Reading?
            do {
                reading = try await TransactionReader.read(item.text)
            } catch is CancellationError {
                return
            } catch {
                // Such as a language the model doesn't support. The rules' reading stays.
                reading = nil
            }
            guard !Task.isCancelled else { return }
            // The person may have added or dismissed it meanwhile.
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { continue }
            var updated = items[index]
            updated.wasRead = true
            if let reading {
                if !reading.description.isEmpty { updated.description = reading.description }
                if updated.amount == nil, let amount = reading.amount {
                    updated.amount = amount
                    updated.currencyCode = updated.currencyCode ?? reading.currencyCode
                }
            }
            try? commit { $0[index] = updated }
        }
    }

    private func loadIfNeeded() throws {
        guard !isLoaded, let file else { return }
        items = try file.load()
        isLoaded = true
    }

    private func commit(_ change: (inout [CapturedTransaction]) -> Void) throws {
        var changed = items
        change(&changed)
        do {
            try file?.save(changed)
        } catch {
            Self.logger.error("Can't save the inbox: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        items = changed
    }
}
