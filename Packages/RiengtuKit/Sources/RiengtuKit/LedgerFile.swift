import Foundation

/// Where builds before the database kept the ledger, as JSON. `LedgerStore` reads it once, moves
/// it to the database (`LedgerDatabase`), and deletes it.
///
/// On iOS the file is encrypted with the device's passcode and can't be read while the device is
/// locked (complete file protection).
public struct LedgerFile: Sendable {
    public enum LoadError: Error, Equatable {
        /// The file is from a later version of the app.
        case newerVersion(Int)
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `ledger.json` in the app's Application Support folder, which isn't visible in Files.
    public static var applicationSupport: LedgerFile {
        LedgerFile(url: .applicationSupportDirectory.appending(path: "ledger.json"))
    }

    /// The ledger in the file, or `nil` if there's no file.
    ///
    /// Throws `LoadError` or `DecodingError` if the file can't be understood, and other errors if
    /// it can't be read now, such as while the device is locked.
    ///
    /// A version 5 file's assets had what entries changed added to their values, so they read as
    /// valued at `now`, and those entries don't count again.
    public func load(now: Date = .now) throws -> Ledger? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).version
        guard version <= Ledger.currentVersion else { throw LoadError.newerVersion(version) }
        var ledger = try decoder.decode(Ledger.self, from: data)
        if version >= 5 { ledger.valueAssets(at: now) }
        return ledger
    }

    /// Deletes the file, if there is one.
    public func delete() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        }
    }

    /// Renames the file so a new ledger can start, keeping the old one on disk in case a later
    /// version can read it. Returns where it went.
    @discardableResult
    public func setAside(now: Date = .now) throws -> URL {
        let stamp = Int(now.timeIntervalSince1970)
        let name = "\(url.deletingPathExtension().lastPathComponent)-unreadable-\(stamp).json"
        let destination = url.deletingLastPathComponent().appending(path: name)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    private struct Header: Decodable {
        var version: Int
    }
}
