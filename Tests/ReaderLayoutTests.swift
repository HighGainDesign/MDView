import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import MDView

@MainActor
final class ReaderLayoutTests: XCTestCase {
    func testArabicDocumentAtLargeZoomUsesRTLTextAndConfinesWideTables() async throws {
        let source = "# خطة العمل\n\nهذه وثيقة للمراجعة والقراءة.\n\n| المهمة | النتيجة |\n| --- | --- |\n| مهمة طويلة للمراجعة | نتيجة مفصلة للعمل المطلوب |\n\n```swift\nlet result = \"Example code\"\n```\n"
        let output = try await MarkdownRenderer.shared.render(source,wide:true,documentLanguage:"ar")
        let reader = ReaderState()
        let coordinator = MarkdownWebView.Coordinator(reader:reader)
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame:NSRect(x:0,y:0,width:480,height:500),configuration:configuration)
        let window = NSWindow(contentRect:web.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = web; window.makeKeyAndOrderFront(nil)
        defer { window.close(); reader.stop() }
        coordinator.webView = web; web.navigationDelegate = coordinator; web.pageZoom = 1.6
        coordinator.load(output.html)
        for _ in 0..<200 {
            if !web.isLoading, let ready = try? await web.evaluateJavaScript("!!document.querySelector('pre')") as? Bool, ready { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        let result = try await web.evaluateJavaScript("""
        ({direction:getComputedStyle(document.querySelector('main')).direction,
          code:getComputedStyle(document.querySelector('pre')).direction,
          overflow:document.documentElement.scrollWidth-document.documentElement.clientWidth})
        """) as! [String:Any]
        XCTAssertEqual(result["direction"] as? String,"rtl")
        XCTAssertEqual(result["code"] as? String,"ltr")
        XCTAssertLessThanOrEqual(result["overflow"] as! Double,1,"Wide tables must scroll inside their container")
    }

    func testRTLReaderWithOutlineAndReviewKeepsBothPanesReadable() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at:file) }
        let reader = ReaderState(); reader.fileURL = file; reader.source = "# Notes\n\nOriginal text.\n\n## Next\n\nMore text.\n"
        try reader.source.write(to:file,atomically:true,encoding:.utf8)
        let controller = NSHostingController(rootView:ReaderView(reader:reader).environment(\.layoutDirection,.rightToLeft))
        let window = NSWindow(contentViewController:controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width:1000,height:760)); window.makeKeyAndOrderFront(nil)
        defer { window.close(); reader.stop() }
        for _ in 0..<200 where reader.rendered == nil { try await Task.sleep(for:.milliseconds(20)) }
        let updated = "# Notes\n\nUpdated text.\n\n## Next\n\nMore text.\n"
        try updated.write(to:file,atomically:true,encoding:.utf8); reader.acceptFileUpdate(updated)
        reader.showOutline = true; reader.showChanges = true
        var documentRect:NSRect?, reviewRect:NSRect?
        for _ in 0..<200 {
            controller.view.layoutSubtreeIfNeeded()
            if let web = findWebView(controller.view), let panel = findReviewPanel(controller.view) {
                documentRect = web.convert(web.bounds,to:controller.view)
                reviewRect = panel.convert(panel.bounds,to:controller.view)
                if documentRect!.height > 150, reviewRect!.height > 150 { break }
            }
            try await Task.sleep(for:.milliseconds(20))
        }
        let document = try XCTUnwrap(documentRect), review = try XCTUnwrap(reviewRect)
        XCTAssertFalse(document.intersects(review))
        XCTAssertGreaterThan(document.width,240)
        XCTAssertGreaterThan(review.width,280)
        XCTAssertTrue(controller.view.bounds.insetBy(dx:-1,dy:-1).contains(review))
        XCTAssertEqual(try MarkdownSource.read(file),updated)
    }

    private func findWebView(_ view:NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWebView(child) { return web } }
        return nil
    }
    private func findReviewPanel(_ view:NSView) -> NSView? {
        if let split = view as? NSSplitView, split.arrangedSubviews.count == 2,
           let panel = split.arrangedSubviews.first(where:{findWebView($0) == nil}) { return panel }
        for child in view.subviews { if let panel = findReviewPanel(child) { return panel } }
        return nil
    }
}
