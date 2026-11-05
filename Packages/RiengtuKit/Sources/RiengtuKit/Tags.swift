import Foundation

/// How tag names are tidied and compared.
///
/// A tag is its name, such as "Work" or "Đà Lạt trip". Two names are the same tag when they
/// match ignoring case and extra spaces, but not diacritics: "Tết" and "Tet" are different words.
public enum Tags {
    /// The tags a ledger starts with, stored in English. The app shows them in the person's
    /// language; tags the person makes are stored and shown as they named them.
    public static let starter = ["Personal", "Family", "Work", "Gift", "Trip"]

    /// `name` without spaces at the ends, and with runs of spaces inside made one.
    public static func tidy(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The tag in `list` that `name` matches, in the list's spelling.
    public static func match(_ name: String, in list: [String]) -> String? {
        let key = key(name)
        return list.first { Self.key($0) == key }
    }

    /// `names` without repeats, in their order.
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert(key($0)).inserted }
    }

    private static func key(_ name: String) -> String {
        tidy(name).folding(options: .caseInsensitive, locale: nil)
    }
}
