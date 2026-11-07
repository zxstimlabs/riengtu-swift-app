import Foundation

/// The JSON file builds 8 and earlier kept the inbox in. `InboxStore` moves what's in it into the
/// inbox's database (`InboxDatabase`) once, and deletes it.
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
