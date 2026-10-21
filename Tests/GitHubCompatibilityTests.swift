import Foundation
import SwiftSoup
import WebKit
import XCTest
@testable import MDView

final class GitHubCompatibilityTests: XCTestCase {
    func testAuthoredImageDimensionsArePreservedWithoutActiveAttributes() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        <img src="images/diagram.png" alt="Diagram" width="320" height="180" onerror="alert(1)" srcset="https://tracker.example/x 2x" style="position:fixed">
        """)
        let image = try XCTUnwrap(try SwiftSoup.parse(result.html).select("img").first())
        XCTAssertEqual(try image.attr("width"), "320")
        XCTAssertEqual(try image.attr("height"), "180")
        XCTAssertTrue(try image.attr("src").hasPrefix("mdview-resource://local/"))
        XCTAssertFalse(image.hasAttr("onerror"))
        XCTAssertFalse(image.hasAttr("srcset"))
        XCTAssertFalse(image.hasAttr("style"))
    }

    func testPassiveGitHubFormattingAndCoreGFMFeaturesRender() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        ~~Old wording~~ and https://example.com

        | Item | Status |
        | --- | ---: |
        | Plan | Ready |

        <details><summary>More detail</summary><p>Some <sup>extra</sup> information.</p></details>
        """)
        let body = try XCTUnwrap(try SwiftSoup.parse(result.html).body())
        XCTAssertEqual(try body.select("del").text(), "Old wording")
        XCTAssertEqual(try body.select("a[href=https://example.com]").size(), 1)
        XCTAssertEqual(try body.select("table").size(), 1)
        XCTAssertEqual(try body.select("details > summary").text(), "More detail")
        XCTAssertEqual(try body.select("sup").text(), "extra")
    }

    func testRawHTMLRemainsInertAndRemoteImagesStillNeedOptIn() async throws {
        let source = """
        <script>alert('bad')</script>
        <iframe src="https://example.com"></iframe>
        <img src="https://example.com/image.png" width="300" onload="alert(1)">
        <img src="javascript:alert(1)" width="calc(100vh)" height="-2">
        <a href="javascript:alert(1)" onclick="alert(2)">Dangerous link</a>
        """
        let blocked = try await MarkdownRenderer.shared.render(source)
        let body = try XCTUnwrap(try SwiftSoup.parse(blocked.html).body())
        XCTAssertEqual(try body.select("script, iframe, [onload], [onclick]").size(), 0)
        let images = try body.select("img").array()
        XCTAssertEqual(images.count, 2)
        XCTAssertFalse(try XCTUnwrap(images.first).hasAttr("src"))
        let invalid = try XCTUnwrap(images.last)
        XCTAssertFalse(invalid.hasAttr("src"))
        XCTAssertFalse(invalid.hasAttr("width"))
        XCTAssertFalse(invalid.hasAttr("height"))
        XCTAssertFalse(try XCTUnwrap(body.select("a").first()).hasAttr("href"))
        let allowed = try await MarkdownRenderer.shared.render(source, loadRemoteImages: true)
        XCTAssertEqual(try SwiftSoup.parse(allowed.html).select("img[src=https://example.com/image.png]").size(), 1)
    }

    func testAuthorHTMLInputsCannotBecomeTasksOrDisruptRealTaskMapping() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        <input type="checkbox" checked>

        - [ ] A real Markdown task
        """, mapTasks: true)
        XCTAssertEqual(result.checkboxCount, 1)
        XCTAssertEqual(result.tasks.map(\.label), ["A real Markdown task"])
        XCTAssertEqual(try SwiftSoup.parse(result.html).select("input[data-mdview-task]").size(), 1)
    }

    func testHTMLHeadingsHaveUniqueOutlineTargetsAndCommonFormattingSurvives() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        <h2>A raw heading</h2><h2>Another heading</h2>
        <details open><summary>Keys</summary><kbd>⌘P</kbd> and <b>bold</b></details>
        <a href="java&#9;script:alert(1)">Unsafe destination</a>
        """)
        XCTAssertEqual(result.headings.count, 2)
        XCTAssertTrue(result.headings.allSatisfy { !$0.id.isEmpty })
        XCTAssertEqual(Set(result.headings.map(\.id)).count, 2)
        let body = try XCTUnwrap(try SwiftSoup.parse(result.html).body())
        XCTAssertEqual(try body.select("kbd").text(), "⌘P")
        XCTAssertEqual(try body.select("b").text(), "bold")
        XCTAssertTrue(try XCTUnwrap(body.select("details").first()).hasAttr("open"))
        XCTAssertFalse(try XCTUnwrap(body.select("a").first()).hasAttr("href"))
    }

    @MainActor
    func testWebKitHonorsAuthoredImageWidthAndHeight() async throws {
        let image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5iQAAAAASUVORK5CYII="
        let result = try await MarkdownRenderer.shared.render("<img src=\"\(image)\" width=\"320\" height=\"180\" alt=\"Example\">")
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        web.loadHTMLString(result.html, baseURL: nil)
        var size: [Double]?
        for _ in 0..<100 {
            size = try? await web.evaluateJavaScript("(() => { const image = document.querySelector('img'); return image?.complete && image.naturalWidth ? [image.width, image.height] : null; })()") as? [Double]
            if size != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(size, [320, 180])
    }
}
