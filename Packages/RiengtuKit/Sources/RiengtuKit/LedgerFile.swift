import Foundation

/// Where the ledger is kept on disk, as JSON.
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

    /// The ledger in the file, or `nil` if there's no file yet.
    ///
    /// Throws `LoadError` or `DecodingError` if the file can't be understood, and other errors if
    /// it can't be read now, such as while the device is locked.
    public func load() throws -> Ledger? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).version
        guard version <= Ledger.currentVersion else { throw LoadError.newerVersion(version) }
        return try decoder.decode(Ledger.self, from: data)
    }

    /// Replaces the file with `ledger`, all at once, so a failed write leaves the old file whole.
    public func save(_ ledger: Ledger) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ledger)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
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
