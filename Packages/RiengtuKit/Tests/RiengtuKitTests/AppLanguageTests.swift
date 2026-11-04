import Testing
@testable import RiengtuKit

struct AppLanguageTests {
    @Test(arguments: zip(
        ["en", "en-US", "en_GB", "vi", "vi-VN", "vi_VN"],
        [AppLanguage.english, .english, .english, .vietnamese, .vietnamese, .vietnamese]
    ))
    func readsIdentifiers(identifier: String, language: AppLanguage) {
        #expect(AppLanguage(identifier: identifier) == language)
    }

    @Test(arguments: ["fr", "zh-Hans", "", "Base"])
    func hasNoOtherLanguages(identifier: String) {
        #expect(AppLanguage(identifier: identifier) == nil)
    }

    @Test func prefersTheFirstLanguageItHas() {
        #expect(AppLanguage.preferred(from: ["fr", "vi-VN", "en"]) == .vietnamese)
        #expect(AppLanguage.preferred(from: ["en-AU", "vi"]) == .english)
    }

    @Test func fallsBackToEnglish() {
        #expect(AppLanguage.preferred(from: ["fr", "de"]) == .english)
        #expect(AppLanguage.preferred(from: []) == .english)
    }
}
