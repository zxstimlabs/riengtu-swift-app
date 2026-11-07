import Foundation

/// Brings transactions added before a rule existed up to date, when the person asks (Settings >
/// Update Past Transactions): each update fills in only what's empty, as a transaction would be
/// read now. Updates are rules, not the model, so they're quick and give the same answer each
/// time. When reading learns something new that the ledger can be filled in with, add it here.
public enum PastTransactions {
    /// The entries that would change, as they'd be. Not ones a later version saved, which this
    /// one can't change.
    public static func updates(in ledger: Ledger, messages: (Entry.ID) -> String?) -> [Entry] {
        ledger.entries.compactMap { entry in
            guard !ledger.newerIDs.contains(entry.id) else { return nil }
            var updated = entry
            findParty(in: &updated, message: messages(entry.id))
            return updated == entry ? nil : updated
        }
    }

    /// Who sent the money or got it, where an expense or income has no party
    /// (`TransactionText.party`): at the start of its note, as banks write a transfer ("NGUYEN VAN
    /// AN chuyen tien"), which then keeps only the rest; or in the bank's message it was added
    /// from, while the inbox's history keeps it.
    static func findParty(in entry: inout Entry, message: String?) {
        guard entry.party.isEmpty, entry.flow != .neither else { return }
        if let name = TransactionText.party(in: entry.note) {
            entry.party = name
            entry.note = TransactionText.removingParty(name, from: entry.note)
        } else if let message, let name = TransactionText.party(in: message) {
            entry.party = name
        }
    }
}
