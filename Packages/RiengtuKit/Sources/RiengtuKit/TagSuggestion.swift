import Foundation

/// A category and tags suggested for an expense, checked against the person's tags.
public struct TagSuggestion: Equatable, Sendable {
    public var category: ExpenseCategory?
    /// Tags from the person's list, spelled as in it.
    public var tags: [String]
    /// A tag the list doesn't have, which the person can add by choosing it.
    public var newTag: String?

    /// The most tags suggested at once.
    public static let maximumTags = 2
    /// A new tag longer than this is dropped: a tag is a word or two, not a sentence.
    public static let newTagMaximumLength = 30

    public init(category: ExpenseCategory? = nil, tags: [String] = [], newTag: String? = nil) {
        self.category = category
        self.tags = tags
        self.newTag = newTag
    }

    /// Checks what a model answered: an unknown category is dropped, tags not in `list` are
    /// dropped, and a new tag that's already in the list counts as one of its tags.
    ///
    /// A new tag must also share a word with `note`, such as "Phú Quốc trip" for "Vé máy bay đi
    /// Phú Quốc", so the model can't make one up from nothing in the note.
    public init(category: String?, tags: [String], newTag: String?, list: [String], note: String) {
        self.category = category.flatMap(ExpenseCategory.init(rawValue:))

        var tags = tags.compactMap { Tags.match($0, in: list) }
        let newTag = newTag.map(Tags.tidy) ?? ""
        if let existing = Tags.match(newTag, in: list) {
            tags.append(existing)
            self.newTag = nil
        } else {
            let isACategory = ExpenseCategory(rawValue: newTag.lowercased()) != nil
            let fits = !newTag.isEmpty && newTag.count <= Self.newTagMaximumLength
            let noteWords = Self.words(in: note)
            let isInNote = Self.words(in: newTag).contains { $0.count > 1 && noteWords.contains($0) }
            self.newTag = fits && !isACategory && isInNote ? newTag : nil
        }
        self.tags = Array(Tags.unique(tags).prefix(Self.maximumTags))
    }

    /// The words in `text`, ignoring case but not diacritics.
    private static func words(in text: String) -> Set<String> {
        Set(text.folding(options: .caseInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init))
    }

    public var isEmpty: Bool {
        category == nil && tags.isEmpty && newTag == nil
    }
}
