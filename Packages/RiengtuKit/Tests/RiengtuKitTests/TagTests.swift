import Foundation
import Testing
@testable import RiengtuKit

struct TagTests {
    static func expense(_ note: String = "", tags: [String] = [], day: Int = 1) -> Expense {
        Expense(amount: 50_000, currencyCode: "VND", category: .food, date: LedgerTests.date(day), note: note, tags: tags)
    }

    @Test func tidiesAndMatchesNamesIgnoringCaseButNotDiacritics() {
        #expect(Tags.tidy("  Đà   Lạt  trip ") == "Đà Lạt trip")
        #expect(Tags.match("work", in: ["Personal", "Work"]) == "Work")
        #expect(Tags.match(" đà lạt TRIP", in: ["Đà Lạt trip"]) == "Đà Lạt trip")
        #expect(Tags.match("Tet", in: ["Tết"]) == nil)
    }

    @Test func addsTheStarterTagsOnceInEnglish() {
        var ledger = Ledger()
        #expect(ledger.needsStarterTags)
        ledger.addStarterTags()
        #expect(ledger.tags == ["Personal", "Family", "Work", "Gift", "Trip"])

        for tag in Tags.starter {
            ledger.deleteTag(tag)
        }
        ledger.addStarterTags()
        #expect(ledger.tags.isEmpty)
        #expect(!ledger.needsStarterTags)
    }

    @Test func addsATagOnce() {
        var ledger = Ledger(tags: [])
        #expect(ledger.addTag(" Work ") == "Work")
        #expect(ledger.addTag("WORK") == "Work")
        #expect(ledger.addTag("   ") == nil)
        #expect(ledger.tags == ["Work"])
    }

    @Test func savesAnExpensesTagsInTheListsSpellingAndAddsNewOnes() {
        var ledger = Ledger(tags: ["Work"])
        ledger.save(Self.expense(tags: ["work", "Đà Lạt trip", "WORK"]))
        #expect(ledger.expenses[0].tags == ["Work", "Đà Lạt trip"])
        #expect(ledger.tags == ["Work", "Đà Lạt trip"])
    }

    @Test func renamesATagEverywhere() {
        var ledger = Ledger(tags: ["Work", "Trip"])
        ledger.save(Self.expense(tags: ["Work"]))
        ledger.renameTag("Work", to: "Công việc")
        #expect(ledger.tags == ["Công việc", "Trip"])
        #expect(ledger.expenses[0].tags == ["Công việc"])

        // Only the case changes.
        ledger.renameTag("Trip", to: "trip")
        #expect(ledger.tags == ["Công việc", "trip"])
    }

    @Test func mergesATagRenamedToAnotherOnesName() {
        var ledger = Ledger(tags: ["Work", "Job"])
        ledger.save(Self.expense(tags: ["Job", "Work"]))
        ledger.save(Self.expense(tags: ["Job"], day: 2))
        ledger.renameTag("Job", to: "work")

        #expect(ledger.tags == ["Work"])
        #expect(ledger.expenses.map(\.tags) == [["Work"], ["Work"]])
    }

    @Test func deletesATagButKeepsTheExpenses() {
        var ledger = Ledger(tags: ["Work", "Trip"])
        ledger.save(Self.expense(tags: ["Work", "Trip"]))
        ledger.deleteTag("work")
        #expect(ledger.tags == ["Trip"])
        #expect(ledger.expenses.map(\.tags) == [["Trip"]])
    }

    @Test func countsAndFiltersByTag() {
        var ledger = Ledger(tags: ["Work"])
        let lunch = Self.expense("Lunch", tags: ["Work"], day: 3)
        ledger.save(lunch)
        ledger.save(Self.expense("Phở", day: 2))
        ledger.save(Self.expense("Taxi", tags: ["Work"], day: 1))

        #expect(ledger.expenseCount(taggedWith: "Work") == 2)
        let days = ledger.days(in: LedgerTests.calendar, taggedWith: "Work")
        #expect(days.flatMap(\.expenses).map(\.note) == ["Lunch", "Taxi"])
        #expect(ledger.days(in: LedgerTests.calendar).count == 3)
    }

    @Test func keepsTagsThroughJSON() throws {
        var ledger = Ledger(tags: ["Work"])
        ledger.save(Self.expense(tags: ["Work"]))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        #expect(decoded == ledger)
        #expect(decoded.expenses[0].tags == ["Work"])

        // No tags left is different from never having had the starter tags.
        let emptied = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(Ledger(tags: [])))
        #expect(!emptied.needsStarterTags)
    }

    @Test func readsAFileWithoutTagsAsNeedingTheStarterTags() throws {
        let version2 = #"{"version": 2, "expenses": [], "assets": [], "recentCurrencyCodes": []}"#
        let ledger = try JSONDecoder().decode(Ledger.self, from: Data(version2.utf8))
        #expect(ledger.needsStarterTags)
        #expect(ledger.tags.isEmpty)
    }
}

struct TagSuggestionTests {
    static let list = ["Personal", "Family", "Work", "Đà Lạt trip"]

    @Test func keepsOnlyTheListsTagsInItsSpelling() {
        let suggestion = TagSuggestion(category: "food", tags: ["work", "Holiday", "Work"], newTag: nil, list: Self.list, note: "")
        #expect(suggestion == TagSuggestion(category: .food, tags: ["Work"]))
    }

    @Test func dropsAnUnknownCategory() {
        #expect(TagSuggestion(category: "pets", tags: [], newTag: nil, list: Self.list, note: "").category == nil)
    }

    @Test func treatsANewTagFromTheListAsOneOfItsTags() {
        let suggestion = TagSuggestion(category: nil, tags: ["Family"], newTag: " đà lạt TRIP ", list: Self.list, note: "")
        #expect(suggestion.tags == ["Family", "Đà Lạt trip"])
        #expect(suggestion.newTag == nil)
    }

    @Test(arguments: [
        ("  Tết 2027 ", "Lì xì Tết 2027", "Tết 2027"),
        ("Phú Quốc trip", "Vé máy bay đi Phú Quốc", "Phú Quốc trip"),
        ("", "Đám cưới", nil),
        ("food", "food", nil),
        (String(repeating: "x", count: 31), String(repeating: "x", count: 31), nil),
        // Nothing in the note says it.
        ("Wedding", "Đám cưới Lan", nil),
        // Diacritics matter: "Tet" isn't "Tết".
        ("Tet", "Lì xì Tết", nil),
    ] as [(String, String, String?)])
    func keepsANewTagOnlyIfItsShortInTheNoteAndNotACategory(newTag: String, note: String, kept: String?) {
        #expect(TagSuggestion(category: nil, tags: [], newTag: newTag, list: Self.list, note: note).newTag == kept)
    }

    @Test func suggestsAFewTagsAtMost() {
        let suggestion = TagSuggestion(category: nil, tags: Self.list, newTag: nil, list: Self.list, note: "")
        #expect(suggestion.tags.count == TagSuggestion.maximumTags)
    }
}

struct ExpenseTaggerTests {
    @Test func writesTheNoteAndAmountInThePrompt() {
        #expect(ExpenseTagger.prompt(note: "Phở bò", amount: 45_000, currencyCode: "VND") == "Note: Phở bò\nAmount: 45000 VND")
        #expect(ExpenseTagger.prompt(note: "Phở bò", amount: nil, currencyCode: "VND") == "Note: Phở bò")
    }

    @Test func makesASchemaWithAndWithoutTags() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        _ = try ExpenseTagger.schema(tags: [])
        _ = try ExpenseTagger.schema(tags: TagSuggestionTests.list)
    }

    /// Runs the real model, where this Mac has Apple Intelligence turned on. The model's choices
    /// can vary, so this only checks that it answers within what the schema allows.
    @Test(.enabled(if: ExpenseTagger.availability == .available), .timeLimit(.minutes(1)))
    func answersWithTheListsTags() async throws {
        let list = TagSuggestionTests.list
        let suggestion = try await ExpenseTagger.suggest(note: "Phở bò với đồng nghiệp", amount: 90_000, currencyCode: "VND", tags: list)
        #expect(suggestion.category != nil)
        #expect(suggestion.tags.allSatisfy(list.contains))
    }
}
