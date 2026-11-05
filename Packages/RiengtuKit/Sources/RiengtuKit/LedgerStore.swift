import Foundation
import Observation
import os

/// The ledger the app shows, saved to its file after every change.
///
/// A change is saved before it's shown: if saving fails, the change throws and the ledger stays
/// as it was. Nothing is saved until the file has been read, so an unreadable file is never
/// replaced by an empty ledger.
@Observable
public final class LedgerStore {
    public enum Status: Equatable, Sendable {
        /// The file hasn't been read yet. It can't be while the device is locked.
        case notLoaded
        case ready
        /// The file is damaged or from a later version. It's left as it is until the person
        /// chooses to start over.
        case unreadable
    }

    public struct NotReadyError: Error {}

    public private(set) var status: Status
    public private(set) var ledger: Ledger

    @ObservationIgnored private let file: LedgerFile?

    private static let logger = Logger(subsystem: "vn.riengtu", category: "LedgerStore")

    /// A store for the ledger in `file`. Call `load()` before using it.
    public init(file: LedgerFile) {
        self.file = file
        status = .notLoaded
        ledger = Ledger()
    }

    /// A store that keeps `ledger` in memory and saves nothing, for previews and tests.
    public init(inMemory ledger: Ledger = Ledger()) {
        file = nil
        status = .ready
        self.ledger = ledger
    }

    /// Reads the file, unless it has been read already. Safe to call each time the app becomes
    /// active: if the file can't be read now, the next call tries again.
    public func load() {
        guard status == .notLoaded, let file else { return }
        do {
            ledger = try file.load() ?? Ledger()
            status = .ready
        } catch is DecodingError {
            Self.logger.error("The ledger file is damaged.")
            status = .unreadable
        } catch let error as LedgerFile.LoadError {
            Self.logger.error("Can't read the ledger file: \(String(describing: error), privacy: .public)")
            status = .unreadable
        } catch {
            Self.logger.error("Can't read the ledger file yet: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func save(_ expense: Expense) throws {
        try commit { $0.save(expense) }
    }

    public func deleteExpense(id: Expense.ID) throws {
        try commit { $0.deleteExpense(id: id) }
    }

    /// Adds the starter tags, unless they were added before.
    public func addStarterTags() throws {
        guard ledger.needsStarterTags else { return }
        try commit { $0.addStarterTags() }
    }

    public func addTag(_ name: String) throws {
        try commit { $0.addTag(name) }
    }

    public func renameTag(_ name: String, to newName: String) throws {
        try commit { $0.renameTag(name, to: newName) }
    }

    public func deleteTag(_ name: String) throws {
        try commit { $0.deleteTag(name) }
    }

    public func save(_ asset: Asset) throws {
        try commit { $0.save(asset) }
    }

    public func deleteAsset(id: Asset.ID) throws {
        try commit { $0.deleteAsset(id: id) }
    }

    /// Deletes every expense and asset, and the file.
    public func eraseAll() throws {
        guard status == .ready else { throw NotReadyError() }
        try file?.delete()
        ledger = Ledger()
    }

    /// Moves an unreadable file aside and starts an empty ledger.
    public func startOver() throws {
        guard status == .unreadable else { return }
        try file?.setAside()
        ledger = Ledger()
        status = .ready
    }

    private func commit(_ change: (inout Ledger) -> Void) throws {
        guard status == .ready else { throw NotReadyError() }
        var changed = ledger
        change(&changed)
        do {
            try file?.save(changed)
        } catch {
            Self.logger.error("Can't save the ledger: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        ledger = changed
    }
}
