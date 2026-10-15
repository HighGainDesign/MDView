import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import MDView

@MainActor
final class ReaderSpeechTests: XCTestCase {
    func testPlaybackHoldsLatestFileUntilExplicitShowLatestEvenAfterStop() async throws {
        let reader = makeReader(); defer { reader.stop() }
        reader.fileURL = URL(fileURLWithPath: "/tmp/speech-held.md")
        reader.source = "# Original\n\nReading text.\n"; reader.render(); try await settle(reader)
        reader.speech.start()
        XCTAssertTrue(reader.playbackHolding)
        XCTAssertEqual(reader.speech.session.status, .playing)
        reader.receiveFileUpdate("# Latest\n\nAgent text.\n")
        XCTAssertEqual(reader.source, "# Original\n\nReading text.\n")
        XCTAssertTrue(reader.hasPendingFileUpdate)
        reader.speech.stop()
        XCTAssertTrue(reader.playbackHolding)
        XCTAssertEqual(reader.source, "# Original\n\nReading text.\n")
        reader.speech.showLatest(); try await settle(reader)
        XCTAssertFalse(reader.playbackHolding)
        XCTAssertEqual(reader.source, "# Latest\n\nAgent text.\n")
        XCTAssertFalse(reader.hasPendingFileUpdate)
    }

    func testManualPauseRemainsIndependentFromPlaybackHold() async throws {
        let reader = makeReader(); defer { reader.stop() }
        reader.fileURL = URL(fileURLWithPath: "/tmp/manual-pause-speech.md")
        reader.source = "Old text."; reader.render(); try await settle(reader)
        reader.setFileUpdatesPaused(true)
        reader.speech.start(); reader.speech.stop()
        XCTAssertTrue(reader.fileUpdatesPaused)
        XCTAssertFalse(reader.playbackHolding)
        reader.speech.start()
        reader.receiveFileUpdate("New text.")
        reader.setFileUpdatesPaused(false)
        XCTAssertEqual(reader.source, "Old text.", "Resuming file updates cannot replace the spoken version")
        reader.speech.showLatest(); try await settle(reader)
        XCTAssertEqual(reader.source, "New text.")
        XCTAssertFalse(reader.fileUpdatesPaused)
    }

    func testStreamSwitchHoldsTextAndSourceNameTogether() async throws {
        let reader = makeReader(); defer { reader.stop() }
        reader.isStreamingPreview = true
        reader.receiveStreamUpdate("# First draft", sourceName: "Drafts")
        try await settle(reader)
        reader.speech.start()
        reader.receiveStreamUpdate("# Second draft", sourceName: "Other Editor")
        XCTAssertEqual(reader.source, "# First draft")
        XCTAssertEqual(reader.streamSourceName, "Drafts")
        XCTAssertTrue(reader.hasPendingFileUpdate)
        reader.speech.showLatest(); try await settle(reader)
        XCTAssertEqual(reader.source, "# Second draft")
        XCTAssertEqual(reader.streamSourceName, "Other Editor")
    }

    func testChecklistCannotWriteWhilePlayingEvenWithoutPendingExternalChange() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = makeReader(); defer { reader.stop() }
        reader.fileURL = file; reader.source = "- [ ] Task\n"
        try reader.source.write(to: file, atomically: true, encoding: .utf8)
        reader.render(); try await settle(reader); reader.checklistMode = true
        reader.speech.start()
        XCTAssertFalse(reader.requestTaskChecked(0, checked: true))
        reader.setTaskChecked(0, checked: true)
        XCTAssertFalse(reader.checklistSaving)
        XCTAssertEqual(try MarkdownSource.read(file), "- [ ] Task\n")
        reader.speech.stop()
        XCTAssertTrue(reader.requestTaskChecked(0, checked: true))
        try await settle(reader)
        XCTAssertEqual(try MarkdownSource.read(file), "- [x] Task\n")
    }

    func testClosingReaderStopsSpeechAndClearsItsHold() async throws {
        let reader = makeReader()
        reader.source = "Text to read."; reader.render(); try await settle(reader)
        reader.speech.start()
        reader.stop()
        XCTAssertEqual(reader.speech.session.status, .idle)
        XCTAssertFalse(reader.playbackHolding)
    }

    func testNativeCheckboxDisablesDuringPlaybackAndExplainsHowToSave() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        let reader = makeReader(); reader.fileURL = file; reader.source = "- [ ] Task\n"
        try reader.source.write(to: file, atomically: true, encoding: .utf8)
        let controller = NSHostingController(rootView: ReaderView(reader: reader))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 650, height: 500)); window.orderFront(nil)
        defer { window.close(); reader.stop(); try? FileManager.default.removeItem(at: file) }
        var web: WKWebView?
        for _ in 0..<150 {
            web = findWeb(controller.view)
            if !reader.isRendering, let web,
               (try? await web.evaluateJavaScript("document.querySelector('input')?.disabled")) as? Bool == false { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let browser = try XCTUnwrap(web)
        reader.speech.start()
        var disabled = false
        for _ in 0..<100 {
            disabled = (try? await browser.evaluateJavaScript("document.querySelector('input')?.disabled")) as? Bool == true
            if disabled { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(disabled)
        let title = try await browser.evaluateJavaScript("document.querySelector('input').title") as? String
        XCTAssertTrue(title?.contains("Read Aloud") == true)
        reader.speech.stop()
    }

    func testSpeechControllerDoesNotRetainAClosedReader() async throws {
        weak var released: ReaderState?
        do {
            let reader = makeReader(); released = reader
            reader.source = "Reading text."; reader.render(); try await settle(reader)
            reader.speech.start(); reader.stop()
        }
        XCTAssertNil(released)
    }

    func testPendingChecklistConsentMustFinishBeforeSpeechStarts() async throws {
        let reader = makeReader(); defer { reader.stop() }
        reader.fileURL = URL(fileURLWithPath: "/tmp/consent-before-speech.md")
        reader.source = "- [ ] Task\n"; reader.render(); try await settle(reader)
        XCTAssertTrue(reader.requestTaskChecked(0, checked: true))
        reader.speech.start()
        XCTAssertFalse(reader.playbackHolding)
        XCTAssertFalse(reader.speech.session.isActive)
        XCTAssertTrue(reader.showChecklistConfirmation)
    }

    private func findWeb(_ view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.findWeb($0) }.first
    }

    private func makeReader() -> ReaderState {
        let name = "MDViewTests.ReaderSpeech.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        let preferences = SpeechPreferences(defaults: defaults)
        return ReaderState(speechFactory: { reader in
            ReaderSpeech(reader: reader, session: SpeechSession(driver: RecordingSpeechDriver(),
                voices: { [SpeechVoice(id: "test", name: "Test", language: "en-US", quality: 1)] },
                coordinator: SpeechCoordinator()), preferences: preferences, progress: SpeechProgressStore(defaults: defaults))
        })
    }
    private func settle(_ reader: ReaderState) async throws {
        for _ in 0..<300 {
            if !reader.isRendering && !reader.checklistSaving { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Reader operation did not settle")
    }
}
