import AppKit
import SwiftUI
import os

@MainActor
final class MarkdownDocument: NSDocument {
    // AppKit constructs concurrent-reading documents on its opening queue.
    // Create UI state only when first accessed by the main actor.
    lazy var reader = ReaderState()
    nonisolated private let loadedSource = OSAllocatedUnfairLock(initialState: LoadedSource())

    nonisolated override init() { super.init() }

    init(preview: PreviewRequest) {
        super.init()
        reader.source = preview.text
        reader.title = preview.title.isEmpty ? "Drafts Preview" : preview.title
        displayName = reader.title
        let loaded = LoadedSource(text: reader.source, url: nil, title: reader.title)
        loadedSource.withLock { $0 = loaded }
    }

    init(streamingPreview: Bool) {
        super.init()
        reader.isStreamingPreview = streamingPreview
        reader.title = "Live Streaming Preview"
        displayName = reader.title
        let loaded = LoadedSource(title: reader.title)
        loadedSource.withLock { $0 = loaded }
    }

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }
    nonisolated override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override func read(from url: URL, ofType typeName: String) throws {
        let text = try MarkdownSource.read(url)
        loadedSource.withLock { $0 = LoadedSource(text: text, url: url, title: url.lastPathComponent) }
    }

    override func makeWindowControllers() {
        let loaded = loadedSource.withLock { $0 }
        reader.source = loaded.text
        reader.fileURL = loaded.url
        reader.title = loaded.title
        let controller = NSHostingController(rootView: ReaderView(reader: reader))
        let window = NSWindow(contentViewController: controller)
        window.title = reader.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 760))
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        addWindowController(NSWindowController(window: window))
        (NSApp.delegate as? AppDelegate)?.documentDidOpen()
    }

    override func close() {
        reader.stop()
        super.close()
    }
}

private struct LoadedSource: Sendable {
    var text = ""
    var url: URL?
    var title = "Markdown"
}
