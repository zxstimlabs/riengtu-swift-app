import Foundation

/// A language the app is translated into. English is the source language.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case vietnamese = "vi"

    /// The language of a locale or language identifier, such as `vi`, `vi-VN` or `en_GB`, if the
    /// app has it.
    public init?(identifier: String) {
        guard let code = Locale(identifier: identifier).language.languageCode?.identifier else { return nil }
        self.init(rawValue: code)
    }

    /// The first language in `identifiers`, most preferred first, that the app has. English if it
    /// has none of them.
    ///
    /// Pass `Bundle.main.preferredLocalizations` for the language the app is showing now.
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        identifiers.lazy.compactMap(AppLanguage.init(identifier:)).first ?? .english
    }

    /// The language's name in that same language, as language pickers show it. It isn't
    /// translated, so it isn't in the string catalog.
    public var endonym: String {
        switch self {
        case .english: "English"
        case .vietnamese: "Tiếng Việt"
        }
    }
}
