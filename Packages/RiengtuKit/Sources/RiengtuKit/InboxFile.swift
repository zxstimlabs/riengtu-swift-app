import Foundation

/// Where the inbox is kept on disk, as JSON, apart from the ledger.
///
/// Shortcuts automations can capture a payment while the device is locked, when the ledger's
/// file can't be opened (complete file protection). So the inbox has its own file, protected
/// until the person first unlocks the device after it starts: still encrypted, and readable
/// after that first unlock. Items leave it once they're added or dismissed.
public struct InboxFile: Sendable {
    public enum LoadError: Error, Equatable {
        /// The file is from a later version of the app.
        case newerVersion(Int)
    }

    public static let currentVersion = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `inbox.json` in the app's Application Support folder.
    public static var applicationSupport: InboxFile {
        InboxFile(url: .applicationSupportDirectory.appending(path: "inbox.json"))
    }

    /// The items in the file, or none if there's no file yet.
    public func load() throws -> [CapturedTransaction] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let contents = try JSONDecoder().decode(Contents.self, from: data)
        guard contents.version <= Self.currentVersion else { throw LoadError.newerVersion(contents.version) }
        return contents.items
    }

    public func save(_ items: [CapturedTransaction]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Contents(version: Self.currentVersion, items: items))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    public func delete() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        }
    }

    private struct Contents: Codable {
        var version: Int
        var items: [CapturedTransaction]
    }
}
