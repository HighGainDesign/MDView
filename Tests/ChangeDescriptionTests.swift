import XCTest
@testable import MDView

final class ChangeDescriptionTests: XCTestCase {
    func testCheckboxOnlyChangeDescribesBothStates() async throws {
        let output = try await MarkdownRenderer.shared.render("- [x] Review the plan\n",baseline:"- [ ] Review the plan\n")
        let change = try XCTUnwrap(output.changes.entries.first)
        XCTAssertTrue(change.beforeAccessibleText.localizedCaseInsensitiveContains("unchecked"))
        XCTAssertTrue(change.afterAccessibleText.localizedCaseInsensitiveContains("checked"))
        XCTAssertTrue(change.beforeAccessibleText.contains("Review the plan"))
        XCTAssertNotEqual(change.beforeAccessibleText,change.afterAccessibleText)
    }

    func testLinkTargetOnlyChangeDescribesEachDestination() async throws {
        let output = try await MarkdownRenderer.shared.render("[Read the plan](https://example.com/new)\n",baseline:"[Read the plan](https://example.com/old)\n")
        let change = try XCTUnwrap(output.changes.entries.first)
        XCTAssertEqual(change.before,change.after)
        XCTAssertTrue(change.beforeAccessibleText.contains("https://example.com/old"))
        XCTAssertFalse(change.beforeAccessibleText.contains("https://example.com/new"))
        XCTAssertTrue(change.afterAccessibleText.contains("https://example.com/new"))
        XCTAssertNotEqual(change.beforeAccessibleText,change.afterAccessibleText)
    }

    func testImageOnlyChangeHasNonemptyAltAndSourceDescriptions() async throws {
        let output = try await MarkdownRenderer.shared.render("![New diagram](new.png)\n",baseline:"![Old diagram](old.png)\n")
        let change = try XCTUnwrap(output.changes.entries.first)
        XCTAssertTrue(change.beforeAccessibleText.contains("Old diagram"))
        XCTAssertTrue(change.beforeAccessibleText.contains("old.png"))
        XCTAssertTrue(change.afterAccessibleText.contains("New diagram"))
        XCTAssertTrue(change.afterAccessibleText.contains("new.png"))
    }
}
