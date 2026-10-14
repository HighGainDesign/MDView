import Foundation
import Darwin

/// The caller supplies the exact rendered version. Never merge a stale click.
enum ChecklistFileStore {
    @concurrent
    static func setChecked(at url: URL, source: String, task: MarkdownTask, checked: Bool) async throws -> String {
        try await setMarker(at: url, source: source, task: task, marker: checked ? 120 : 32)
    }

    @concurrent
    static func setMarker(at url: URL, source: String, task: MarkdownTask, marker: UInt8) async throws -> String {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<String, Error>?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Result {
                let handle = try FileHandle(forUpdating: coordinatedURL)
                defer { try? handle.close() }
                let original = try handle.read(upToCount: MarkdownSource.maximumBytes + 1) ?? Data()
                let patched = try MarkdownTasks.patch(original, expectedSource: source, task: task, marker: marker)
                guard original != patched else { return source }
                // Refuse an atomic replacement that happened after opening the file.
                var opened = stat(), current = stat()
                guard fstat(handle.fileDescriptor, &opened) == 0,
                      coordinatedURL.path.withCString({ fstatat(AT_FDCWD, $0, &current, 0) }) == 0,
                      opened.st_dev == current.st_dev, opened.st_ino == current.st_ino else { throw ChecklistError.changed }
                // Verify again inside coordinated access, immediately before the write.
                try handle.seek(toOffset: 0)
                guard try handle.read(upToCount: MarkdownSource.maximumBytes + 1) == original else { throw ChecklistError.changed }
                let changed = original.indices.filter { original[$0] != patched[$0] }
                guard let first = changed.first, let last = changed.last else { return source }
                // Write only the one-byte marker (two-byte code unit for UTF-16),
                // preserving all other bytes, permissions, xattrs and the inode.
                try handle.seek(toOffset: UInt64(first))
                try handle.write(contentsOf: patched[first...last])
                try handle.synchronize()
                guard try MarkdownSource.read(coordinatedURL) == MarkdownSource.decode(patched) else { throw ChecklistError.changed }
                return try MarkdownSource.decode(patched)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw ChecklistError.changed }
        return try outcome.get()
    }
}
