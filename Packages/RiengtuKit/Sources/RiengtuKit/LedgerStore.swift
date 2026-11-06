import Foundation
import Observation
import os

/// The ledger the app shows, saved to its database after every change.
///
/// A change is saved before it's shown: if saving fails, the change throws and the ledger stays
/// as it was. Nothing is saved until the database has been read, so data that can't be read is
/// never replaced by an empty ledger.
///
/// On the main actor, where the app uses it, and where `CloudSync` puts what other devices
/// changed.
@MainActor
@Observable
public final class LedgerStore {
    public enum Status: Equatable, Sendable {
        /// The database hasn't been read yet. It can't be while the device is locked.
        case notLoaded
        case ready
        /// The database is damaged, or the file earlier builds kept the ledger in can't be read.
        /// It's left as it is until the person chooses to start over.
        case unreadable
    }

    public struct NotReadyError: Error {}
    /// The entry or asset was saved by a later version of Riêng Tư, which this one could lose
    /// part of by changing it.
    public struct NewerVersionError: Error {}

    /// Where the database is, and the file earlier builds kept the ledger in.
    public struct Location: Sendable {
        public var directory: URL
        public var legacyFile: LedgerFile?

        public init(directory: URL, legacyFile: LedgerFile?) {
            self.directory = directory
            self.legacyFile = legacyFile
        }

        /// A `Ledger` folder in the app's Application Support folder, which isn't visible in
        /// Files, and `ledger.json` beside it from earlier builds.
        public static var applicationSupport: Location {
            Location(directory: .applicationSupportDirectory.appending(path: "Ledger"), legacyFile: .applicationSupport)
        }
    }

    public private(set) var status: Status
    public private(set) var ledger: Ledger
    /// Whether the last `load()` couldn't open the data, for a reason that isn't damage, such as
    /// the device being locked. The next `load()` tries again.
    public private(set) var loadFailed = false

    @ObservationIgnored private let location: Location?
    @ObservationIgnored private(set) var database: LedgerDatabase?
    /// Whether `status` is `unreadable` because the database is damaged.
    @ObservationIgnored private var databaseIsDamaged = false
    /// Called after each change is saved, with the names of the records saved and deleted.
    /// `CloudSync` sends them to iCloud.
    @ObservationIgnored var didChangeRecords: (@MainActor (_ saved: [String], _ deleted: [String]) -> Void)?

    private static let logger = Logger(subsystem: "vn.riengtu", category: "LedgerStore")

    /// A store for the ledger at `location`. Call `load()` before using it.
    public init(location: Location) {
        self.location = location
        status = .notLoaded
        ledger = Ledger()
    }

    /// A store that keeps `ledger` in memory and saves nothing, for previews.
    public init(inMemory ledger: Ledger = Ledger()) {
        location = nil
        status = .ready
        self.ledger = ledger
    }

    /// A store with a database in memory, for tests.
    init(database: LedgerDatabase) throws {
        location = nil
        self.database = database
        ledger = try database.load()
        status = .ready
    }

    /// Opens the database and reads it, unless that's done already, moving the ledger from the
    /// file earlier builds kept it in. Safe to call each time the app becomes active: if the
    /// database can't be opened now, the next call tries again.
    public func load() {
        guard status == .notLoaded, let location else { return }
        do {
            let database = try database ?? LedgerDatabase(directory: location.directory)
            self.database = database
            if let legacyFile = location.legacyFile, let old = try legacyFile.load() {
                try database.importLedger(old)
                try legacyFile.delete()
            }
            ledger = try database.load()
            status = .ready
            loadFailed = false
        } catch let error where LedgerDatabase.isDamaged(error) {
            Self.logger.error("The ledger database is damaged.")
            databaseIsDamaged = true
            status = .unreadable
        } catch is DecodingError {
            Self.logger.error("The ledger file from an earlier build is damaged.")
            status = .unreadable
        } catch let error as LedgerFile.LoadError {
            Self.logger.error("Can't read the ledger file: \(String(describing: error), privacy: .public)")
            status = .unreadable
        } catch {
            Self.logger.error("Can't read the ledger yet: \(error.localizedDescription, privacy: .public)")
            loadFailed = true
        }
    }

    /// Reads the database again, after `CloudSync` saved what other devices changed.
    func reload() {
        guard status == .ready, let database else { return }
        do {
            ledger = try database.load()
        } catch {
            Self.logger.error("Can't read the ledger again: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func save(_ entry: Entry) throws {
        guard !ledger.newerIDs.contains(entry.id) else { throw NewerVersionError() }
        try commit { $0.save(entry) }
    }

    public func deleteEntry(id: Entry.ID) throws {
        try commit { $0.deleteEntry(id: id) }
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

    /// Saves the asset. With a `date`, a change to its worth goes in the ledger as an adjustment
    /// (`Ledger.save(_:recordingChangeOn:)`).
    public func save(_ asset: Asset, recordingChangeOn date: Date? = nil) throws {
        guard !ledger.newerIDs.contains(asset.id) else { throw NewerVersionError() }
        try commit { $0.save(asset, recordingChangeOn: date) }
    }

    public func deleteAsset(id: Asset.ID) throws {
        try commit { $0.deleteAsset(id: id) }
    }

    /// Deletes every entry, asset and tag on this device. `CloudSync.eraseICloudData()` deletes
    /// them in iCloud.
    public func eraseAll() throws {
        guard status == .ready else { throw NotReadyError() }
        try database?.eraseAll()
        ledger = Ledger()
    }

    /// Moves damaged data aside, keeping it on the device in case a later version can read it,
    /// and starts an empty ledger.
    public func startOver() throws {
        guard status == .unreadable, let location else { return }
        let stamp = Int(Date.now.timeIntervalSince1970)
        if let legacyFile = location.legacyFile, FileManager.default.fileExists(atPath: legacyFile.url.path(percentEncoded: false)) {
            try legacyFile.setAside()
        }
        if databaseIsDamaged {
            database = nil
            try FileManager.default.moveItem(
                at: LedgerDatabase.file(in: location.directory),
                to: location.directory.appending(path: "ledger-unreadable-\(stamp).sqlite")
            )
            databaseIsDamaged = false
        }
        status = .notLoaded
        load()
        guard status == .ready else { throw NotReadyError() }
    }

    private func commit(_ change: (inout Ledger) -> Void) throws {
        guard status == .ready else { throw NotReadyError() }
        var changed = ledger
        change(&changed)
        let changes = try LedgerDatabase.Changes(from: ledger, to: changed)
        do {
            if !changes.isEmpty { try database?.write(changes) }
        } catch {
            Self.logger.error("Can't save the ledger: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        ledger = changed
        if !changes.saved.isEmpty || !changes.deleted.isEmpty {
            didChangeRecords?(changes.savedNames, changes.deleted)
        }
    }
}
