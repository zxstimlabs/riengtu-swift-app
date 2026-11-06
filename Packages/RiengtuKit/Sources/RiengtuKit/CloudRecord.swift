import CloudKit
import Foundation

/// How a record in the ledger's database is a CloudKit record, in a zone of the person's private
/// database.
///
/// Every type of record has the same fields: its format's `version` and when it was last
/// changed (`modifiedAt`), which the person's devices compare, and its JSON (`data`), encrypted
/// end to end with keys in the person's iCloud Keychain, so not even Apple can read it. A type a
/// later version adds is kept the same way by earlier ones.
enum CloudRecord {
    static let zoneID = CKRecordZone.ID(zoneName: "Ledger", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let version = "version"
        static let modifiedAt = "modifiedAt"
        static let data = "data"
    }

    static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The CloudKit record for `row`, built on the system fields iCloud last sent, so iCloud can
    /// tell whether it changed since.
    static func make(from row: LedgerDatabase.Row) -> CKRecord {
        let record = row.systemFields.flatMap(record(fromSystemFields:))
            ?? CKRecord(recordType: row.type, recordID: recordID(row.name))
        record[Field.version] = row.version
        record[Field.modifiedAt] = row.modifiedAt
        record.encryptedValues[Field.data] = row.data
        return record
    }

    /// The row for a record from iCloud, or `nil` if it isn't one of the ledger's.
    static func row(from record: CKRecord) -> LedgerDatabase.Row? {
        guard record.recordID.zoneID == zoneID,
              let data = record.encryptedValues[Field.data] as? Data,
              let version = record[Field.version] as? Int
        else { return nil }
        return LedgerDatabase.Row(
            name: record.recordID.recordName,
            type: record.recordType,
            version: version,
            modifiedAt: record[Field.modifiedAt] as? Date ?? record.modificationDate ?? .distantPast,
            data: data,
            systemFields: systemFields(of: record)
        )
    }

    /// The record's system fields, such as its change tag, without its data.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
