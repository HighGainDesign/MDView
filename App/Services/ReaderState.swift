import AppKit
import Observation

@MainActor @Observable
final class ReaderState {
    var source = ""
    var title = "Markdown"
    var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            grantedFolder?.stopAccessingSecurityScopedResource()
            grantedFolder = fileURL.flatMap { ImageFolderAccess.restore(for: $0) }
            imageRoot = grantedFolder ?? fileURL?.deletingLastPathComponent()
            imagePermissionRequired = false
        }
    }
    var rendered: RenderedMarkdown?
    var errorMessage: String?
    var showOutline = false
    var showFind = false
    var searchText = ""
    var searchBackwards = false
    var searchGeneration = 0
    var searchFound = true
    var selectedHeading: String?
    var navigationTarget: String?
    var navigationGeneration = 0
    var currentChangeIndex = -1
    var lastRefreshed: Date?
    var zoom = 1.0
    var wide = UserDefaults.standard.object(forKey: "wideLayout") as? Bool ?? true
    var documentAppearance = DocumentAppearance.system
    var loadRemoteImages = false
    var imageRoot: URL?
    var imagePermissionRequired = false
    var imageAccessGeneration = 0
    private var grantedFolder: URL?
    private var renderTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var reviewedSource: String?

    var changes: ChangeSummary { rendered?.changes ?? ChangeSummary() }

    func navigate(to id: String) {
        navigationTarget = id
        navigationGeneration += 1
    }

    func jumpToChange(backwards: Bool = false) {
        let entries = changes.navigable
        guard !entries.isEmpty else { return }
        if currentChangeIndex < 0 { currentChangeIndex = backwards ? entries.count - 1 : 0 }
        else { currentChangeIndex = (currentChangeIndex + (backwards ? -1 : 1) + entries.count) % entries.count }
        if let target = entries[currentChangeIndex].targetID { navigate(to: target) }
    }

    func markReviewed() {
        reviewedSource = source
        currentChangeIndex = -1
        render()
    }

    func acceptFileUpdate(_ text: String) {
        if reviewedSource == nil { reviewedSource = source }
        lastRefreshed = Date()
        guard text != source else { errorMessage = nil; return }
        source = text
        currentChangeIndex = -1
        render()
    }

    func render() {
        renderTask?.cancel()
        let text = source, title = title, wide = wide, loadRemoteImages = loadRemoteImages
        let appearance = documentAppearance
        let baseline = fileURL == nil ? nil : reviewedSource
        renderTask = Task { [weak self] in
            do {
                let output = try await MarkdownRenderer.shared.render(text, title: title, wide: wide, baseline: baseline, loadRemoteImages: loadRemoteImages, appearance: appearance)
                guard !Task.isCancelled else { return }
                self?.rendered = output
                self?.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Poll the pathname, rather than an inode, to support atomic saves by agents/editors.
    /// The SwiftUI task cancels when its document window closes.
    func watchFile() async {
        if reviewedSource == nil { reviewedSource = source }
        render()
        guard let fileURL else { return }
        var lastStamp = FileStamp(url: fileURL)
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            let stamp = FileStamp(url: fileURL)
            guard stamp != lastStamp || errorMessage != nil else { continue }
            do {
                let newSource = try await MarkdownSource.readInBackground(fileURL)
                guard !Task.isCancelled else { return }
                lastStamp = stamp
                acceptFileUpdate(newSource)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Could not refresh: \(error.localizedDescription)"
            }
        }
    }

    func reload() {
        guard let fileURL else { render(); return }
        readTask?.cancel()
        readTask = Task { [weak self] in
            do {
                let text = try await MarkdownSource.readInBackground(fileURL)
                guard !Task.isCancelled, let self else { return }
                acceptFileUpdate(text)
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func allowImageFolder() {
        guard let fileURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.message = "macOS needs permission to read this document’s images. Choose their folder; MDView remembers read-only access to it."
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        grantedFolder?.stopAccessingSecurityScopedResource()
        grantedFolder = url.startAccessingSecurityScopedResource() ? url : nil
        do { try ImageFolderAccess.remember(url, for: fileURL) }
        catch { errorMessage = "Images are available for this session, but folder access could not be remembered: \(error.localizedDescription)" }
        imageRoot = url
        imagePermissionRequired = false
        imageAccessGeneration += 1
    }

    func changeZoom(by amount: Double) { zoom = min(2.0, max(0.6, zoom + amount)) }

    func stop() {
        renderTask?.cancel()
        readTask?.cancel()
        grantedFolder?.stopAccessingSecurityScopedResource()
        grantedFolder = nil
    }
}

private struct FileStamp: Equatable {
    let modified: Date?
    let size: UInt64?
    let inode: UInt64?

    init(url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        modified = attributes?[.modificationDate] as? Date
        size = attributes?[.size] as? UInt64
        inode = attributes?[.systemFileNumber] as? UInt64
    }
}
