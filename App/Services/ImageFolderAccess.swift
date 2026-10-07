import Foundation

@MainActor
enum ImageFolderAccess {
    private static let key = "imageFolderBookmarks"

    /// Folder access is granted by macOS's picker, and retained read-only.
    /// Bind it to this document directory rather than enabling every saved root.
    static func restore(for document: URL) -> URL? {
        let directory = document.deletingLastPathComponent().standardizedFileURL.path
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: key),
              let data = bookmarks[directory] as? Data else { return nil }
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            guard folder.startAccessingSecurityScopedResource() else { return nil }
            if stale { try? remember(folder, for: document) }
            return folder
        } catch { return nil }
    }

    static func remember(_ folder: URL, for document: URL) throws {
        let data = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                          includingResourceValuesForKeys: nil, relativeTo: nil)
        var bookmarks = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        bookmarks[document.deletingLastPathComponent().standardizedFileURL.path] = data
        UserDefaults.standard.set(bookmarks, forKey: key)
    }
}
