import AppKit
import Observation

@MainActor @Observable
final class ReaderState {
    var source = ""
    var title = "Markdown"
    var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            cancelChecklistConfirmation()
            checklistMode = false
            checklistSaving = false; pendingChecklistSource = nil
            checklistUndo.removeAll(); checklistRedo.removeAll()
            localImageError = nil
        }
    }
    var rendered: RenderedMarkdown?
    var errorMessage: String?
    var showOutline = false
    private var findVisible = false
    private(set) var findFocusGeneration = 0
    // Cmd-F is a focus request even when the Find bar is already visible.
    var showFind: Bool {
        get { findVisible }
        set {
            findVisible = newValue
            if newValue { findFocusGeneration += 1 }
        }
    }
    var showChanges = false
    var searchText = ""
    var searchBackwards = false
    var searchGeneration = 0
    var searchFound = true
    var selectedHeading: String?
    var navigationTarget: String?
    var navigationGeneration = 0
    var currentChangeIndex = -1
    var lastRefreshed: Date?
    var isStreamingPreview = false
    var streamPaused = false
    var streamIsReceiving = false
    var streamSourceName: String?
    var streamError: String?
    var checklistMode = false { didSet { checklistError = nil } }
    var showChecklistConfirmation = false
    private(set) var pendingChecklistConfirmation: ChecklistConfirmation?
    private(set) var checklistSaving = false
    var checklistError: String?
    private var pendingChecklistSource: String?
    private var checklistUndo: [ChecklistOperation] = []
    private var checklistRedo: [ChecklistOperation] = []

    var canUndoChecklist: Bool { checklistMode && !checklistSaving && !isRendering && !checklistUndo.isEmpty }
    var canRedoChecklist: Bool { checklistMode && !checklistSaving && !isRendering && !checklistRedo.isEmpty }
    var zoom = 1.0
    var wide = UserDefaults.standard.object(forKey: "wideLayout") as? Bool ?? true
    var documentAppearance = DocumentAppearance.system
    var loadRemoteImages = false
    var localImageError: String?
    var imageReloadGeneration = 0
    private var renderTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var reviewedSource: String?
    private var reviewedUnits: [ReadingUnit]?
    private var advanceAfterReview = false
    private(set) var isRendering = false

    var changes: ChangeSummary { rendered?.changes ?? ChangeSummary() }
    var selectedChange: DocumentChange? {
        guard !changes.entries.isEmpty else { return nil }
        return changes.entries[min(max(0, currentChangeIndex), changes.count - 1)]
    }

    func navigate(to id: String) {
        navigationTarget = id
        navigationGeneration += 1
    }

    func jumpToChange(backwards: Bool = false) {
        let entries = changes.entries
        guard !entries.isEmpty else { return }
        if currentChangeIndex < 0 { currentChangeIndex = backwards ? entries.count - 1 : 0 }
        else { currentChangeIndex = (currentChangeIndex + (backwards ? -1 : 1) + entries.count) % entries.count }
        if let target = entries[currentChangeIndex].targetID { navigate(to: target) }
    }

    func markReviewed() {
        reviewedSource = source
        reviewedUnits = nil
        advanceAfterReview = false
        currentChangeIndex = -1
        render()
    }

    func markCurrentChangeReviewed() {
        guard !isRendering, let change = selectedChange,
              var baseline = rendered?.comparisonBaseline else { return }
        let offset = change.baselineOffset
        switch change.kind {
        case .added:
            guard offset <= baseline.count, let replacement = change.replacement else { return }
            baseline.insert(replacement, at: offset)
        case .edited:
            guard baseline.indices.contains(offset), let replacement = change.replacement else { return }
            baseline[offset] = replacement
        case .removed:
            guard baseline.indices.contains(offset) else { return }
            baseline.remove(at: offset)
        }
        reviewedUnits = baseline
        currentChangeIndex = max(0, currentChangeIndex)
        advanceAfterReview = true
        render()
    }

    func acceptFileUpdate(_ text: String) {
        if text != source && text != pendingChecklistSource {
            checklistUndo.removeAll(); checklistRedo.removeAll()
        }
        if reviewedSource == nil { reviewedSource = source }
        lastRefreshed = Date()
        guard text != source else { errorMessage = nil; return }
        source = text
        currentChangeIndex = -1
        render()
    }

    struct ChecklistConfirmation {
        let fileURL: URL
        let source: String
        let task: MarkdownTask
        let checked: Bool
    }

    @discardableResult
    func requestTaskChecked(_ id: Int, checked: Bool) -> Bool {
        guard !checklistSaving, !isRendering, !showChecklistConfirmation,
              !isStreamingPreview, let fileURL, let rendered, rendered.taskSource == source,
              let task = rendered.tasks.first(where: { $0.id == id }), task.checked != checked else { return false }
        if checklistMode { setTaskChecked(id, checked: checked) }
        else {
            pendingChecklistConfirmation = ChecklistConfirmation(fileURL: fileURL, source: source, task: task, checked: checked)
            showChecklistConfirmation = true
        }
        return true
    }

    func cancelChecklistConfirmation() {
        showChecklistConfirmation = false
        pendingChecklistConfirmation = nil
    }

    func confirmChecklistSaving() {
        guard let pending = pendingChecklistConfirmation else { return }
        cancelChecklistConfirmation()
        guard pending.fileURL == fileURL, !isStreamingPreview else { return }
        checklistMode = true
        guard pending.source == source else {
            checklistError = ChecklistError.changed.localizedDescription
            reload()
            return
        }
        // The consented gesture already has a validated source descriptor.
        // An appearance-only render need not discard that first change.
        performChecklistChange(task: pending.task, marker: pending.checked ? 120 : 32, history: .normal, allowRendering: true)
    }

    func setTaskChecked(_ id: Int, checked: Bool) {
        guard let rendered, rendered.taskSource == source,
              let task = rendered.tasks.first(where: { $0.id == id }), task.checked != checked else { return }
        performChecklistChange(task: task, marker: checked ? 120 : 32, history: .normal)
    }

    func undoChecklist() {
        guard canUndoChecklist, let operation = checklistUndo.last else { return }
        performChecklistChange(task: operation.task, marker: operation.marker, history: .undo)
    }

    func redoChecklist() {
        guard canRedoChecklist, let operation = checklistRedo.last else { return }
        performChecklistChange(task: operation.task, marker: operation.marker, history: .redo)
    }

    private func performChecklistChange(task: MarkdownTask, marker: UInt8, history: ChecklistHistory, allowRendering: Bool = false) {
        guard checklistMode, !checklistSaving, (!isRendering || allowRendering), !isStreamingPreview, let fileURL else { return }
        let expected = source
        do {
            pendingChecklistSource = try MarkdownSource.decode(MarkdownTasks.patch(Data(expected.utf8), expectedSource: expected, task: task, marker: marker))
        } catch { checklistError = error.localizedDescription; return }
        checklistSaving = true
        checklistError = nil
        Task { [weak self] in
            do {
                let updated = try await ChecklistFileStore.setMarker(at: fileURL, source: expected, task: task, marker: marker)
                guard let self, self.fileURL == fileURL else { return }
                acceptFileUpdate(updated)
                let inverse = ChecklistOperation(task: MarkdownTask(id: task.id, utf8Offset: task.utf8Offset, marker: marker, label: task.label), marker: task.marker)
                switch history {
                case .normal: checklistUndo.append(inverse); checklistRedo.removeAll()
                case .undo: if !checklistUndo.isEmpty { checklistUndo.removeLast() }; checklistRedo.append(inverse)
                case .redo: if !checklistRedo.isEmpty { checklistRedo.removeLast() }; checklistUndo.append(inverse)
                }
                if checklistUndo.count > 100 { checklistUndo.removeFirst() }
                checklistSaving = false
                pendingChecklistSource = nil
            } catch {
                guard let self, self.fileURL == fileURL else { return }
                checklistSaving = false
                pendingChecklistSource = nil
                checklistError = error.localizedDescription
                checklistUndo.removeAll(); checklistRedo.removeAll()
                reload()
            }
        }
    }

    private enum ChecklistHistory { case normal, undo, redo }
    private struct ChecklistOperation { let task: MarkdownTask; let marker: UInt8 }

    func render() {
        renderTask?.cancel()
        isRendering = true
        let text = source, title = title, wide = wide, loadRemoteImages = loadRemoteImages
        let appearance = documentAppearance
        let baseline = fileURL == nil ? nil : reviewedSource
        let units = fileURL == nil ? nil : reviewedUnits
        renderTask = Task { [weak self] in
            do {
                let output = try await MarkdownRenderer.shared.render(text, title: title, wide: wide, baseline: baseline, reviewedUnits: units, loadRemoteImages: loadRemoteImages, appearance: appearance, mapTasks: self?.fileURL != nil)
                guard !Task.isCancelled else { return }
                self?.rendered = output
                self?.errorMessage = nil
                self?.isRendering = false
                if let self {
                    currentChangeIndex = output.changes.count == 0 ? -1 : min(max(0, currentChangeIndex), output.changes.count - 1)
                    if advanceAfterReview {
                        advanceAfterReview = false
                        if let target = selectedChange?.targetID { navigate(to: target) }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = error.localizedDescription
                self?.isRendering = false
            }
        }
    }

    /// Poll the pathname, rather than an inode, to support atomic saves by agents/editors.
    /// The SwiftUI task cancels when its document window closes.
    func watchFile() async {
        if isStreamingPreview { await watchStream(); return }
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

    func watchStream(_ stream: MarkdownStream = MarkdownStream()) async {
        render()
        var lastCount: Int?
        while !Task.isCancelled && isStreamingPreview {
            if !streamPaused {
                do {
                    if let snapshot = try stream.read(after: lastCount) {
                        lastCount = snapshot.count
                        streamError = nil
                        switch snapshot.update {
                        case .waiting:
                            streamIsReceiving = false
                            streamSourceName = nil
                        case .text(let text, let sourceName):
                            streamSourceName = sourceName
                            streamIsReceiving = true
                            lastRefreshed = Date()
                            if source != text { source = text; render() }
                        }
                    }
                } catch {
                    lastCount = stream.pasteboard.changeCount
                    streamIsReceiving = false
                    streamError = "Could not read live preview: \(error.localizedDescription)"
                }
            }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    func reload() {
        localImageError = nil
        imageReloadGeneration += 1
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

    func changeZoom(by amount: Double) { zoom = min(2.0, max(0.6, zoom + amount)) }

    func stop() {
        cancelChecklistConfirmation()
        checklistMode = false
        streamPaused = true
        isStreamingPreview = false
        renderTask?.cancel()
        readTask?.cancel()
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
