import Foundation
import XCTest
@testable import MDView

final class LocalizationTests: XCTestCase {
    func testEnglishWordCountUsesSingularAndPluralCatalogForms() {
        let locale = Locale(identifier:"en")
        XCTAssertEqual(String(localized:"\(1) words",locale:locale),"1 word")
        XCTAssertEqual(String(localized:"\(2) words",locale:locale),"2 words")
        XCTAssertEqual(String(localized:"\(0) words",locale:locale),"0 words")
    }

    func testEnglishChangesAndRemainingCountHaveSingularForms() {
        let locale = Locale(identifier:"en")
        XCTAssertEqual(String(localized:"\(1) unreviewed changes available.",locale:locale),"1 unreviewed change available.")
        XCTAssertEqual(String(localized:"\(2) unreviewed changes available.",locale:locale),"2 unreviewed changes available.")
        XCTAssertEqual(String(localized:"\(1) changes remaining.",locale:locale),"1 change remaining.")
        XCTAssertEqual(String(localized:"\(1) unreviewed changes, panel \("shown")",locale:locale),"1 unreviewed change, panel shown")
    }
}

extension LocalizationTests {
    func testCompiledTranslationsAndPluralForms() throws {
        let examples: [(String, String, String, String)] = [
            ("es", "Leer en voz alta", "1 palabra", "2 palabras"),
            ("zh-Hans", "朗读", "1 字", "2 字"),
            ("zh-Hant", "朗讀", "1 字", "2 字"),
            ("ja", "読み上げ", "1 語", "2 語"),
            ("fr", "Lire à voix haute", "1 mot", "2 mots"),
            ("de", "Vorlesen", "1 Wort", "2 Wörter")
        ]
        for (language, title, singular, plural) in examples {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "Missing compiled \(language)")
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Read Aloud", value: nil, table: nil), title)
            XCTAssertEqual(String(localized: "\(1) words", bundle: bundle, locale: Locale(identifier: language)), singular)
            XCTAssertEqual(String(localized: "\(2) words", bundle: bundle, locale: Locale(identifier: language)), plural)
        }
    }
}
