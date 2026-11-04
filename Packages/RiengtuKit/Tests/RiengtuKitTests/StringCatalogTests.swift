import Foundation
import Testing
@testable import RiengtuKit

/// Checks the app's string catalogs, which live outside this package: every string the app shows
/// must be in every language it has. `Localizable.xcstrings` has the app's text, and
/// `InfoPlist.xcstrings` what iOS shows for it, such as the reason it asks for Face ID.
struct StringCatalogTests {
    static let catalogNames = ["Localizable", "InfoPlist"]

    static func catalogURL(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent() // RiengtuKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RiengtuKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // the repository
            .appending(path: "App/\(name).xcstrings")
    }

    @Test(arguments: catalogNames)
    func sourceLanguageIsEnglish(catalog name: String) throws {
        let catalog = try StringCatalog.load(from: Self.catalogURL(name))
        #expect(catalog.sourceLanguage == AppLanguage.english.rawValue)
    }

    /// A string that's new in the catalog, or whose English changed, fails until it's translated
    /// and marked so. Strings no longer in the code (stale) and ones marked "Don't Translate" are
    /// left out.
    @Test(arguments: catalogNames, AppLanguage.allCases.filter { $0 != .english })
    func everyStringIsTranslated(catalog name: String, into language: AppLanguage) throws {
        let catalog = try StringCatalog.load(from: Self.catalogURL(name))
        let untranslated = catalog.strings
            .filter { _, entry in entry.shouldTranslate != false && entry.extractionState != "stale" }
            .filter { _, entry in entry.localizations?[language.rawValue]?.isTranslated != true }
            .map(\.key)
            .sorted()
        #expect(untranslated.isEmpty, "Not translated into \(language.endonym) in \(name): \(untranslated)")
    }
}

/// The parts of an `.xcstrings` file the tests read.
private struct StringCatalog: Decodable {
    var sourceLanguage: String
    var strings: [String: Entry]

    struct Entry: Decodable {
        var extractionState: String?
        var shouldTranslate: Bool?
        var localizations: [String: Localization]?
    }

    /// One language's text for a string: a single string unit, or variations, by plural or by
    /// device, that each hold one.
    struct Localization: Decodable {
        var stringUnit: StringUnit?
        var variations: [String: [String: Localization]]?

        var isTranslated: Bool {
            if let variations {
                let cases = variations.values.flatMap(\.values)
                return !cases.isEmpty && cases.allSatisfy(\.isTranslated)
            }
            return stringUnit?.state == "translated" && stringUnit?.value.isEmpty == false
        }
    }

    struct StringUnit: Decodable {
        var state: String
        var value: String
    }

    static func load(from url: URL) throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }
}
