import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import MDView

@MainActor
final class ReadingPositionTests: XCTestCase {
    func testInsertionAboveViewportPreservesAnchorFocusSelectionAndImageNodes() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        let web = fixture.web
        fixture.window.makeFirstResponder(web)
        let before = try await web.callAsyncJavaScript("""
        window.savedHeading = document.getElementById('mdview-section-30');
        window.savedInput = document.querySelector('input[data-mdview-task="30"]');
        window.savedImage = document.querySelector('img');
        window.savedText = window.savedHeading.nextElementSibling.nextElementSibling.firstChild;
        window.savedInput.focus({preventScroll:true});
        const range = document.createRange(); range.selectNodeContents(window.savedText);
        window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
        window.scrollTo({top: window.savedHeading.getBoundingClientRect().top + window.scrollY - 25, behavior:'instant'});
        return {top:window.savedHeading.getBoundingClientRect().top, y:window.scrollY};
        """, arguments: [:], in: nil, contentWorld: MarkdownWebView.Coordinator.taskWorld) as! [String:Double]
        let updated = "# Inserted above\n\n" + String(repeating: "Additional context above the reading position. ", count: 30) + "\n\n" + fixture.source
        fixture.reader.acceptFileUpdate(updated)
        try await waitForHeading("mdview-inserted-above", in: web)
        let result = try await web.callAsyncJavaScript("""
        return {
          heading: window.savedHeading === document.getElementById('mdview-section-30'),
          input: window.savedInput === document.querySelector('input[data-mdview-task="30"]'),
          image: window.savedImage === document.querySelector('img'),
          focus: document.activeElement === window.savedInput,
          selection: getSelection().anchorNode === window.savedText,
          top: document.getElementById('mdview-section-30').getBoundingClientRect().top,
          y: window.scrollY
        };
        """, arguments: [:], in: nil, contentWorld: MarkdownWebView.Coordinator.taskWorld) as! [String:Any]
        for key in ["heading","input","image","focus","selection"] {
            XCTAssertEqual(result[key] as? Bool, true, "Refresh lost the existing \(key)")
        }
        XCTAssertEqual(result["top"] as! Double, before["top"]!, accuracy: 2)
        XCTAssertGreaterThan(result["y"] as! Double, before["y"]! + 100)
        XCTAssertEqual(try MarkdownSource.read(fixture.file), fixture.source, "Rendering must never write the file")
    }

    func testRemovedReadingAnchorUsesNextSurvivingBlock() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        _ = try await fixture.web.callAsyncJavaScript("""
        const anchor = document.getElementById('mdview-section-30');
        window.scrollTo({top: anchor.getBoundingClientRect().top + scrollY - 25, behavior:'instant'});
        """, arguments: [:], in: nil, contentWorld: MarkdownWebView.Coordinator.taskWorld)
        fixture.reader.acceptFileUpdate(fixture.source.replacingOccurrences(of: Self.section(30), with: ""))
        for _ in 0..<200 {
            if !fixture.reader.isRendering,
               let gone = try? await fixture.web.evaluateJavaScript("!document.getElementById('mdview-section-30')") as? Bool, gone { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let top = try await fixture.web.evaluateJavaScript("document.getElementById('mdview-section-31').getBoundingClientRect().top") as! Double
        XCTAssertEqual(top, 25, accuracy: 2, "A removed anchor should fall forward to the next surviving reading block")
    }

    func testPolicyNavigationRestoresSemanticAnchorRatherThanAbsoluteOffset() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        _ = try await fixture.web.callAsyncJavaScript("""
        const anchor = document.getElementById('mdview-section-30');
        window.scrollTo({top: anchor.getBoundingClientRect().top + scrollY - 25, behavior:'instant'});
        window.oldDocument = document;
        """, arguments: [:], in: nil, contentWorld: MarkdownWebView.Coordinator.taskWorld)
        fixture.reader.loadRemoteImages = true
        for _ in 0..<200 {
            if let allowed = try? await fixture.web.evaluateJavaScript("document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content.includes('https:')") as? Bool, allowed { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(100))
        let top = try await fixture.web.evaluateJavaScript("document.getElementById('mdview-section-30').getBoundingClientRect().top") as! Double
        XCTAssertEqual(top, 25, accuracy: 2)
        let sameDocument = try await fixture.web.callAsyncJavaScript("return window.oldDocument === document;", arguments: [:], in: nil, contentWorld: MarkdownWebView.Coordinator.taskWorld) as! Bool
        XCTAssertFalse(sameDocument)
    }

    func testFindRequestedDuringSaveKeepsTypingFocusAfterSaveCompletes() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        fixture.reader.checklistMode = true
        fixture.window.makeFirstResponder(fixture.web)
        _ = try await fixture.web.callAsyncJavaScript("""
        window.webkit.messageHandlers.taskToggle.postMessage({id:30,checked:true,token:window.mdviewTaskState.token});
        """,arguments:[:],in:nil,contentWorld:MarkdownWebView.Coordinator.taskWorld)
        fixture.reader.showFind = true
        for _ in 0..<200 {
            if !fixture.reader.checklistSaving, !fixture.reader.isRendering,
               fixture.reader.source.contains("- [x] Task 30"),
               fixture.window.firstResponder is NSTextView { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertTrue(fixture.window.firstResponder is NSTextView,"An earlier checkbox gesture must not steal a newer Find request")
        XCTAssertTrue(fixture.reader.source.contains("- [x] Task 30"))
    }

    func testHeadingJumpFocusesDestinationAndNewerFindKeepsTypingFocus() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        fixture.reader.showFind = true
        for _ in 0..<100 where !(fixture.window.firstResponder is NSTextView) { try await Task.sleep(for:.milliseconds(20)) }
        fixture.reader.navigate(to:"mdview-section-40")
        for _ in 0..<100 {
            if let id = try? await fixture.web.evaluateJavaScript("document.activeElement.id") as? String, id == "mdview-section-40" { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        let id = try await fixture.web.evaluateJavaScript("document.activeElement.id") as? String
        XCTAssertEqual(id,"mdview-section-40","Outline navigation must focus its heading, not just scroll")
        XCTAssertFalse(fixture.window.firstResponder is NSTextView,"Explicit document navigation should leave the Find field")
        fixture.reader.navigate(to:"mdview-section-41")
        fixture.reader.showFind = true
        for _ in 0..<100 where !(fixture.window.firstResponder is NSTextView) { try await Task.sleep(for:.milliseconds(20)) }
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertTrue(fixture.window.firstResponder is NSTextView,"A queued jump must not override a newer Find request")
        XCTAssertEqual(try MarkdownSource.read(fixture.file),fixture.source)
    }

    func testUncheckedTaskShortcutsSkipCheckedTasksWrapAndDoNotWrite() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        fixture.reader.acceptFileUpdate(fixture.source.replacingOccurrences(of:"- [ ] Task 0\n",with:"- [x] Task 0\n"))
        for _ in 0..<200 {
            if !fixture.reader.isRendering,
               let checked = try? await fixture.web.evaluateJavaScript("document.querySelector('input').defaultChecked") as? Bool, checked { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        fixture.reader.jumpToUncheckedTask()
        try await waitForActiveTask("1", in:fixture.web)
        fixture.reader.jumpToUncheckedTask(backwards:true)
        try await waitForActiveTask("59", in:fixture.web)
        fixture.reader.jumpToUncheckedTask()
        try await waitForActiveTask("1", in:fixture.web)
        XCTAssertEqual(try MarkdownSource.read(fixture.file),fixture.source)
    }

    func testDocumentEntryKeepsReadingPositionAndReturnsToFind() async throws {
        let fixture = try await fixture()
        defer { fixture.close() }
        _ = try await fixture.web.callAsyncJavaScript("""
        const heading = document.getElementById('mdview-section-30');
        window.scrollTo({top:scrollY+heading.getBoundingClientRect().top-25,behavior:'instant'});
        """,arguments:[:],in:nil,contentWorld:MarkdownWebView.Coordinator.taskWorld)
        fixture.reader.showFind = true
        for _ in 0..<100 where !(fixture.window.firstResponder is NSTextView) { try await Task.sleep(for:.milliseconds(20)) }
        fixture.reader.focusDocument()
        for _ in 0..<100 {
            if let focused = try? await fixture.web.evaluateJavaScript("document.activeElement.id === 'mdview-section-30'") as? Bool, focused { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        let top = try await fixture.web.evaluateJavaScript("document.getElementById('mdview-section-30').getBoundingClientRect().top") as! Double
        XCTAssertEqual(top,25,accuracy:2)
        XCTAssertFalse(fixture.window.firstResponder is NSTextView)
        fixture.reader.returnToNavigation()
        for _ in 0..<100 where !(fixture.window.firstResponder is NSTextView) { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertTrue(fixture.window.firstResponder is NSTextView)
        XCTAssertEqual(try MarkdownSource.read(fixture.file),fixture.source)
    }

    private func waitForActiveTask(_ id:String,in web:WKWebView) async throws {
        for _ in 0..<100 {
            if let actual = try? await web.evaluateJavaScript("document.activeElement.dataset.mdviewTask") as? String, actual == id { return }
            try await Task.sleep(for:.milliseconds(20))
        }
        let actual = try? await web.evaluateJavaScript("document.activeElement.outerHTML")
        XCTFail("Expected task \(id) focus, got \(String(describing:actual))")
    }

    @MainActor private struct Fixture {
        let reader: ReaderState
        let window: NSWindow
        let web: WKWebView
        let file: URL
        let source: String
        func close() { window.close(); reader.stop(); try? FileManager.default.removeItem(at: file) }
    }

    private static func section(_ index: Int) -> String {
        "## Section \(index)\n\n- [ ] Task \(index)\n\n" + String(repeating: "Reading context for section \(index). ", count: 12) + "\n\n"
    }

    private func fixture() async throws -> Fixture {
        let image = "![Context image](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5iQAAAAASUVORK5CYII=)\n\n"
        let source = "# Reading\n\n" + image + (0..<60).map { Self.section($0) }.joined()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let reader = ReaderState(); reader.fileURL = file; reader.source = source
        reader.render()
        let controller = NSHostingController(rootView: ReaderView(reader: reader))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 500)); window.makeKeyAndOrderFront(nil)
        for _ in 0..<200 {
            if !reader.isRendering, let web = findWebView(controller.view), !web.isLoading,
               let ready = try? await web.evaluateJavaScript("!!document.getElementById('mdview-section-30') && !document.querySelector('input').disabled") as? Bool, ready {
                return Fixture(reader:reader,window:window,web:web,file:file,source:source)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        window.close(); reader.stop(); try? FileManager.default.removeItem(at: file)
        throw NSError(domain: "ReadingPositionTests",code:1,userInfo:[NSLocalizedDescriptionKey:"Reader did not load"])
    }

    private func waitForHeading(_ id: String, in web: WKWebView) async throws {
        for _ in 0..<200 {
            if let ready = try? await web.callAsyncJavaScript("return !!document.getElementById(id);",arguments:["id":id],in:nil,contentWorld:MarkdownWebView.Coordinator.taskWorld) as? Bool, ready { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Updated heading did not appear")
    }

    private func findWebView(_ view:NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWebView(child) { return web } }
        return nil
    }
}
