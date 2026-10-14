import AppKit

/// Resolves the active editor before falling back to the document's checklist.
@MainActor
struct ReaderUndo {
    let responder: NSResponder?
    let reader: ReaderState?

    private var editor: NSTextView? {
        guard let editor = responder as? NSTextView, editor.isEditable else { return nil }
        return editor
    }

    var isEditingText: Bool { editor != nil }
    var canUndo: Bool { editor.map { $0.undoManager?.canUndo == true } ?? (reader?.canUndoChecklist == true) }
    var canRedo: Bool { editor.map { $0.undoManager?.canRedo == true } ?? (reader?.canRedoChecklist == true) }

    func undo() {
        if let editor { if editor.undoManager?.canUndo == true { editor.undoManager?.undo() } }
        else { reader?.undoChecklist() }
    }

    func redo() {
        if let editor { if editor.undoManager?.canRedo == true { editor.undoManager?.redo() } }
        else { reader?.redoChecklist() }
    }
}
