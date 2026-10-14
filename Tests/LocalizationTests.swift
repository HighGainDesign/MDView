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
