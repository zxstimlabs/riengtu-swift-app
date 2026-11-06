import CloudKit
import Foundation
import Observation
import os

/// Keeps the ledger in the person's iCloud account when they turn it on, so it's on each of their
/// devices, with Apple's `CKSyncEngine`.
///
/// Each entry, asset and tag is a record (`CloudRecord`), its data encrypted end to end. A change
/// is saved to the database first, marked to send, and sent while the app is open: syncing stops
/// in the background, where the database can't be opened once the device locks, and starts again
/// from where it was. Where two devices changed the same record, the later change wins, except
/// over a record in a later format.
///
/// If the iCloud account changes, or the ledger is deleted from iCloud, such as by Erase All Data
/// on another device, syncing turns off and what's on this device stays.
@MainActor
@Observable
public final class CloudSync {
    public enum Status: Equatable, Sendable {
        case off
        /// Checking the account, or sending and fetching changes.
        case syncing
        case upToDate(Date)
        /// There's no iCloud account on the device, or it can't be used.
        case noAccount
        /// Syncing turned off because the device's iCloud account changed.
        case accountChanged
        /// Syncing turned off because the ledger was deleted from iCloud.
        case deletedFromICloud
        /// Something went wrong. Syncing tries again.
        case failed
    }

    public private(set) var status: Status
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let store: LedgerStore
    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var isStarting = false
    /// Whether iCloud refused a record in the last send for a reason trying again won't fix, such
    /// as a record type the Production schema doesn't have yet.
    @ObservationIgnored private var sendWasRefused = false

    /// Whether syncing is on. A setting, not ledger data, so it can live in `UserDefaults`.
    static let enabledKey = "syncsWithICloud"

    private static let logger = Logger(subsystem: "vn.riengtu", category: "CloudSync")

    public init(store: LedgerStore, containerIdentifier: String = "iCloud.vn.riengtu", defaults: UserDefaults = .standard) {
        self.store = store
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        status = .off
        store.didChangeRecords = { [weak self] saved, deleted in
            self?.send(saved: saved, deleted: deleted)
        }
    }

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    // MARK: Turning it on and off

    /// Starts syncing, if it's on and the ledger is open. Call it each time the app becomes
    /// active.
    public func start() {
        guard isEnabled, engine == nil, !isStarting, store.status == .ready, store.database != nil else { return }
        isStarting = true
        status = .syncing
        Task {
            defer { isStarting = false }
            guard await accountIsAvailable() else {
                status = .noAccount
                return
            }
            // It may have been turned off meanwhile.
            guard isEnabled, engine == nil, store.status == .ready, let database = store.database else { return }
            startEngine(with: database)
        }
    }

    /// Stops syncing until `start()`. What's left to send stays marked in the database. Call it
    /// when the app goes to the background.
    public func stop() {
        engine = nil
        delegate = nil
    }

    /// Turns syncing on, sending everything on this device and fetching what's in iCloud, or
    /// off. Turning it off leaves the ledger in iCloud.
    public func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        if enabled {
            status = .syncing
            guard await accountIsAvailable() else {
                status = .noAccount
                return
            }
            do {
                try store.database?.resetSync(uploadingEverything: true)
            } catch {
                Self.logger.error("Can't mark the ledger to send: \(error.localizedDescription, privacy: .public)")
                status = .failed
                return
            }
            setIsEnabled(true)
            start()
        } else {
            turnOff(status: .off)
        }
    }

    /// Deletes the ledger from iCloud, for every device: their syncing turns off, and what's on
    /// them stays. Throws if it can't, such as while offline. Syncing stays on, starting afresh.
    public func eraseICloudData() async throws {
        guard isEnabled else { return }
        stop()
        let results = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [CloudRecord.zoneID])
        if case .failure(let error)? = results.deleteResults[CloudRecord.zoneID], (error as? CKError)?.code != .zoneNotFound {
            throw error
        }
        try store.database?.resetSync(uploadingEverything: false)
    }

    private func accountIsAvailable() async -> Bool {
        do {
            return try await container.accountStatus() == .available
        } catch {
            Self.logger.error("Can't check the iCloud account: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func setIsEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    /// Stops syncing and forgets how far it got, keeping the ledger on this device.
    private func turnOff(status: Status) {
        stop()
        do {
            try store.database?.resetSync(uploadingEverything: false)
        } catch {
            Self.logger.error("Can't forget the sync state: \(error.localizedDescription, privacy: .public)")
        }
        setIsEnabled(false)
        self.status = status
    }

    private func startEngine(with database: LedgerDatabase) {
        let state: CKSyncEngine.State.Serialization?
        do {
            state = try database.syncState().map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        } catch {
            Self.logger.error("Can't read the sync state: \(error.localizedDescription, privacy: .public)")
            state = nil
        }
        let delegate = Delegate(sync: self)
        let engine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: delegate
        ))
        self.delegate = delegate
        self.engine = engine
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
        }
        sendPendingChanges(with: engine, from: database)
    }

    // MARK: Sending

    /// Adds what the database marks to send to the engine's pending changes.
    private func sendPendingChanges(with engine: CKSyncEngine, from database: LedgerDatabase) {
        do {
            let pending = try database.pendingChanges()
            let changes = pending.saved.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudRecord.recordID($0)) }
                + pending.deleted.map { .deleteRecord(CloudRecord.recordID($0)) }
            let queued = Set(engine.state.pendingRecordZoneChanges)
            engine.state.add(pendingRecordZoneChanges: changes.filter { !queued.contains($0) })
        } catch {
            Self.logger.error("Can't read the changes to send: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sends what the person changed, once syncing runs.
    private func send(saved: [String], deleted: [String]) {
        engine?.state.add(pendingRecordZoneChanges:
            saved.map { .saveRecord(CloudRecord.recordID($0)) } + deleted.map { .deleteRecord(CloudRecord.recordID($0)) }
        )
    }

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, from engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === self.engine, let database = store.database else { return nil }
        let scope = context.options.scope
        var changes = engine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let names = changes.compactMap { change -> String? in
            if case .saveRecord(let id) = change { id.recordName } else { nil }
        }
        let rows: [String: LedgerDatabase.Row]
        do {
            rows = try database.rows(named: names)
        } catch {
            Self.logger.error("Can't read the records to send: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // Records deleted since they changed: their deletion is pending instead.
        let gone = names.filter { rows[$0] == nil }.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudRecord.recordID($0)) }
        if !gone.isEmpty {
            engine.state.remove(pendingRecordZoneChanges: gone)
            changes.removeAll { gone.contains($0) }
        }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            rows[id.recordName].map(CloudRecord.make(from:))
        }
    }

    // MARK: Events

    fileprivate func handle(_ event: CKSyncEngine.Event, from engine: CKSyncEngine) {
        guard engine === self.engine, let database = store.database else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                try database.setSyncState(JSONEncoder().encode(update.stateSerialization))

            case .accountChange(let change):
                switch change.changeType {
                case .signIn:
                    break
                case .signOut, .switchAccounts:
                    turnOff(status: .accountChanged)
                @unknown default:
                    break
                }

            case .fetchedDatabaseChanges(let changes):
                for deletion in changes.deletions where deletion.zoneID == CloudRecord.zoneID {
                    switch deletion.reason {
                    case .encryptedDataReset:
                        // The keys were reset, so what's in iCloud can't be read: send it all again.
                        try database.resetSync(uploadingEverything: true)
                        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
                        sendPendingChanges(with: engine, from: database)
                    default:
                        turnOff(status: .deletedFromICloud)
                        return
                    }
                }

            case .fetchedRecordZoneChanges(let changes):
                let rows = changes.modifications.compactMap { CloudRecord.row(from: $0.record) }
                var changed = try database.receive(rows)
                if try database.receiveDeletions(changes.deletions.map(\.recordID.recordName)) {
                    changed = true
                }
                if changed { store.reload() }
                // Records changed here that another device deleted are made again.
                sendPendingChanges(with: engine, from: database)

            case .sentRecordZoneChanges(let sent):
                try handle(sent, from: engine, database: database)

            case .sentDatabaseChanges(let sent):
                for failure in sent.failedZoneSaves {
                    Self.logger.error("Can't save the zone: \(failure.error.code.rawValue, privacy: .public)")
                }

            case .willSendChanges:
                sendWasRefused = false
                status = .syncing

            case .willFetchChanges:
                status = .syncing

            case .didSendChanges:
                status = sendWasRefused ? .failed : .upToDate(.now)

            case .didFetchChanges:
                if !sendWasRefused { status = .upToDate(.now) }

            case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
                break

            @unknown default:
                break
            }
        } catch {
            Self.logger.error("Can't sync a change: \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }

    private func handle(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, from engine: CKSyncEngine, database: LedgerDatabase) throws {
        for record in sent.savedRecords {
            try database.didUpload(
                record.recordID.recordName,
                systemFields: CloudRecord.systemFields(of: record),
                modifiedAt: record[CloudRecord.Field.modifiedAt] as? Date ?? .distantPast
            )
        }

        var retries: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        var changed = false
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device changed it too. The later change wins.
                guard let server = failure.error.serverRecord, let row = CloudRecord.row(from: server) else { continue }
                if try database.receive([row]) { changed = true }
                if try database.rows(named: [id.recordName])[id.recordName]?.needsUpload == true {
                    retries.append(.saveRecord(id))
                }
            case .zoneNotFound:
                needsZone = true
                try database.forgetSystemFields(of: id.recordName)
                retries.append(.saveRecord(id))
            case .unknownItem:
                // Deleted in iCloud: made again with this device's change.
                try database.forgetSystemFields(of: id.recordName)
                retries.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .requestRateLimited:
                // The engine tries again.
                break
            default:
                Self.logger.error("Can't save a record: \(failure.error.code.rawValue, privacy: .public)")
                sendWasRefused = true
            }
        }
        if needsZone {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudRecord.zoneID))])
        }
        engine.state.add(pendingRecordZoneChanges: retries)
        if changed { store.reload() }

        try database.didDelete(sent.deletedRecordIDs.map(\.recordName))
        // Ones iCloud never had, or that went with their zone, are deleted already.
        let gone = sent.failedRecordDeletes.filter { $0.value.code == .unknownItem || $0.value.code == .zoneNotFound }
        try database.didDelete(gone.keys.map(\.recordName))
    }
}

/// Passes the engine's calls to `CloudSync`, on the main actor.
private final class Delegate: CKSyncEngineDelegate {
    let sync: CloudSync

    init(sync: CloudSync) {
        self.sync = sync
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await sync.handle(event, from: syncEngine)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await sync.nextBatch(context, from: syncEngine)
    }
}
