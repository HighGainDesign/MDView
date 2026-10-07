import Foundation
import XCTest
import WebKit
@testable import MDView

final class MarkdownTests: XCTestCase {
    func testTablesLinksCodeAndTasks() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        # Plan
        | Name | Value |
        | :--- | ---: |
        | **Fast** | 42 |

        [Web](https://example.com) and https://example.org
        - [x] Finished
        - [ ] Pending

        ```swift
        let value = "<script>"
        ```
        """)
        XCTAssertTrue(result.html.contains("<table"))
        XCTAssertTrue(result.html.contains("<strong>Fast</strong>"))
        XCTAssertTrue(result.html.contains("align=\"right\""))
        XCTAssertTrue(result.html.contains("href=\"https://example.org\""))
        XCTAssertTrue(result.html.contains("type=\"checkbox\""))
        XCTAssertTrue(result.html.contains("checked"))
        XCTAssertTrue(result.html.contains("disabled"))
        XCTAssertTrue(result.html.contains("Pending"))
        XCTAssertTrue(result.html.contains("language-swift"))
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
        XCTAssertEqual(result.headings.map(\.title), ["Plan"])
    }

    func testUntrustedContentIsInertAndRemoteImagesAreBlocked() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        <script>alert('x')</script>
        [bad](javascript:alert(1))
        ![tracker](https://example.com/private.png)
        ![file](file:///etc/passwd)
        ![local](images/screenshot.png)
        """, title: "</title><script>bad</script>")
        XCTAssertFalse(result.html.contains("<script>"))
        XCTAssertFalse(result.html.contains("href=\"javascript:"))
        XCTAssertFalse(result.html.contains("src=\"https:"))
        XCTAssertFalse(result.html.contains("src=\"file:"))
        XCTAssertTrue(result.html.contains("mdview-resource://local/images%2Fscreenshot%2Epng"))
        XCTAssertTrue(result.html.contains("default-src 'none'"))
    }

    func testHeadingAnchorsUnicodeAndDuplicateTitles() async throws {
        let result = try await MarkdownRenderer.shared.render("# Hello **world**\n# Hello world\n## 日本語\n[Jump](#hello-world)")
        XCTAssertEqual(result.headings.map(\.id), ["mdview-hello-world", "mdview-hello-world-1", "mdview-header"])
        XCTAssertEqual(result.headings.last?.title, "日本語")
        XCTAssertEqual(result.headings.map(\.level), [1, 1, 2])
        XCTAssertTrue(result.html.contains("href=\"#mdview-hello-world\""))
    }

    func testEmptyAndWideDocuments() async throws {
        let result = try await MarkdownRenderer.shared.render("", wide: true)
        XCTAssertEqual(result.wordCount, 0)
        XCTAssertEqual(result.headings, [])
        XCTAssertTrue(result.html.contains("body class=\"wide\""))
    }

    func testApexFootnotesAndBlockquotes() async throws {
        let result = try await MarkdownRenderer.shared.render("""
        A note with a footnote.[^note]

        [^note]: A useful detail.

        > [!NOTE]
        > Keep this nearby.
        """)
        XCTAssertTrue(result.html.contains("A useful detail."))
        XCTAssertTrue(result.html.contains("footnote"))
        XCTAssertTrue(result.html.contains("Keep this nearby."))
        XCTAssertTrue(result.html.contains("blockquote"))
        XCTAssertTrue(result.html.contains("[!NOTE]"))
    }

    func testDraftsURLPreservesUnicodeAndReservedCharacters() throws {
        let text = "# Café\nA & B + 100% = 日本語\n[link](https://example.com?a=1&b=2)"
        var components = URLComponents()
        components.scheme = "mdview"
        components.host = "preview"
        components.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "title", value: "A&B")]
        let result = try PreviewRequest(url: XCTUnwrap(components.url))
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.title, "A&B")
        XCTAssertThrowsError(try PreviewRequest(url: XCTUnwrap(URL(string: "mdview://preview?title=Missing"))))
        XCTAssertThrowsError(try PreviewRequest(url: XCTUnwrap(URL(string: "https://preview?text=bad"))))
    }

    func testBundledDraftsActionIsPortableAndLeavesDraftUntouched() throws {
        let bundle = Bundle(for: MarkdownDocument.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Preview in MDView", withExtension: "draftsAction"))
        let action = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(action["name"] as? String, "Preview in MDView")
        XCTAssertEqual(action["disposition"] as? Int, 0)
        XCTAssertEqual(action["backingAssignFlag"] as? Int, 0)
        XCTAssertEqual((action["assignTags"] as? [String])?.count, 0)
        XCTAssertNil(action["groupUUID"])
        let steps = try XCTUnwrap(action["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0]["type"] as? String, "url")
        XCTAssertEqual(steps[0]["platforms"] as? Int, 2)
        let data = try XCTUnwrap(steps[0]["data"] as? [String: String])
        XCTAssertEqual(data["encodeTags"], "true")
        XCTAssertEqual(data["template"], "mdview://preview?text=[[draft]]&title=[[title]]")
    }

    func testStartupGuideSuppressionIsOptionalAndSurvivesRelaunch() throws {
        let suite = "MDViewTests.StartupTips.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(StartupTips.shouldShow(defaults: defaults))
        StartupTips.finish(dontShowAgain: false, defaults: defaults)
        XCTAssertTrue(StartupTips.shouldShow(defaults: defaults))
        StartupTips.finish(dontShowAgain: true, defaults: defaults)
        XCTAssertFalse(StartupTips.shouldShow(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))))
        StartupTips.finish(dontShowAgain: false, defaults: defaults)
        XCTAssertTrue(StartupTips.shouldShow(defaults: defaults))
    }

    func testRemoteImagesRequireExplicitOptInAndStayHTTPSOnly() async throws {
        let source = """
        ![secure](https://example.com/image.png)
        ![http](http://example.com/image.png)
        ![credentials](https://user:secret@example.com/image.png)
        ![file](file:///etc/passwd)
        ![protocol-relative](//example.com/image.png)
        ![script](javascript:alert(1))
        ![local](images/example.png)
        """
        let allowed = try await MarkdownRenderer.shared.render(source, loadRemoteImages: true)
        XCTAssertTrue(allowed.html.contains("src=\"https://example.com/image.png\""))
        XCTAssertTrue(allowed.html.contains("img-src mdview-resource: data: https:;"))
        XCTAssertTrue(allowed.html.contains("referrerpolicy=\"no-referrer\""))
        XCTAssertTrue(allowed.html.contains("name=\"referrer\" content=\"no-referrer\""))
        for scheme in ["http:", "file:", "javascript:", "//", "https://user:"] {
            XCTAssertFalse(allowed.html.contains("src=\"" + scheme))
        }
        XCTAssertTrue(allowed.html.contains("mdview-resource://local/"))
        let blockedAgain = try await MarkdownRenderer.shared.render(source)
        XCTAssertFalse(blockedAgain.html.contains("src=\"https:"))
        XCTAssertFalse(blockedAgain.html.contains("data: https:;"))
    }

    @MainActor
    func testRemoteImagesAndWidthAreIndependentPerDocument() {
        let first = ReaderState()
        let second = ReaderState()
        XCTAssertFalse(first.loadRemoteImages)
        first.loadRemoteImages = true
        first.wide.toggle()
        XCTAssertFalse(second.loadRemoteImages)
        XCTAssertEqual(second.wide, UserDefaults.standard.object(forKey: "wideLayout") as? Bool ?? true)
        XCTAssertFalse(ReaderState().loadRemoteImages)
    }

    func testEncodingAndDocumentSizeLimits() throws {
        XCTAssertEqual(try MarkdownSource.decode(Data([0xef, 0xbb, 0xbf]) + Data("# Note".utf8)), "# Note")
        XCTAssertEqual(try MarkdownSource.decode(XCTUnwrap("# Note".data(using: .utf16))), "# Note")
        XCTAssertThrowsError(try MarkdownSource.decode(Data([0xff, 0x80, 0x00])))
        XCTAssertThrowsError(try MarkdownSource.decode(Data(repeating: 65, count: MarkdownSource.maximumBytes + 1)))
    }

    func testLocalImagesStayInsideGrantedFolder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("notes/plan.md")
        XCTAssertEqual(LocalImage.resolve("../assets/image.png", documentURL: file, allowedRoot: root)?.lastPathComponent, "image.png")
        XCTAssertNil(LocalImage.resolve("../../private.png", documentURL: file, allowedRoot: root))
        XCTAssertNil(LocalImage.resolve("/etc/passwd", documentURL: file, allowedRoot: root))
        XCTAssertNil(LocalImage.resolve("image.svg", documentURL: file, allowedRoot: root))
        XCTAssertNil(LocalImage.resolve("file:///tmp/image.png", documentURL: file, allowedRoot: root))
    }

    @MainActor
    func testLocalImagesDefaultToDocumentFolderAndRejectEscapingSymlinks() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = workspace.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data([0]).write(to: workspace.appendingPathComponent("private.png"))
        let file = root.appendingPathComponent("plan.md")
        let reader = ReaderState()
        reader.fileURL = file
        XCTAssertEqual(reader.imageRoot?.path, root.path)
        XCTAssertNotNil(LocalImage.resolve("images/figure.png", documentURL: file, allowedRoot: root))
        XCTAssertNil(LocalImage.resolve("../private.png", documentURL: file, allowedRoot: root))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"),
                                                  withDestinationURL: workspace)
        XCTAssertNil(LocalImage.resolve("outside/private.png", documentURL: file, allowedRoot: root))
    }

    @MainActor
    func testFirstWebViewLoadDisplaysMarkdown() async throws {
        let reader = ReaderState()
        let rendered = try await MarkdownRenderer.shared.render("# Visible on first load")
        let coordinator = MarkdownWebView.Coordinator(reader: reader)
        let webView = WKWebView(frame: .zero)
        coordinator.webView = webView
        webView.navigationDelegate = coordinator
        coordinator.load(rendered.html)
        for _ in 0..<100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotNil(webView.url)
        let text = try await webView.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(text?.contains("Visible on first load") == true)
    }

    @MainActor
    func testBackgroundDocumentInitialization() async throws {
        // Match NSDocumentController's concurrent opening queue; this used to
        // trap in the Objective-C thunk for a main-actor-isolated initializer.
        let constructed = await Task.detached {
            _ = MarkdownDocument()
            return true
        }.value
        XCTAssertTrue(constructed)
    }

    @MainActor
    func testDocumentIsReadOnlyAndDraftsPreviewStaysInMemory() throws {
        let request = try PreviewRequest(url: XCTUnwrap(URL(string: "mdview://preview?text=Hello&title=Draft")))
        let document = MarkdownDocument(preview: request)
        XCTAssertNil(document.fileURL)
        XCTAssertEqual(document.reader.source, "Hello")
        XCTAssertEqual(document.reader.title, "Draft")
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertFalse(MarkdownDocument.autosavesInPlace)
    }
}
