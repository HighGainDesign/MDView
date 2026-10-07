import Foundation

enum LocalImage {
    /// Resolve relative paths inside a user-granted folder, including symlink resolution.
    static func resolve(_ relativePath: String, documentURL: URL, allowedRoot: URL) -> URL? {
        guard !relativePath.hasPrefix("/"), !relativePath.contains(":") else { return nil }
        let path = relativePath.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
        guard let decoded = path.removingPercentEncoding else { return nil }
        let target = documentURL.deletingLastPathComponent().appendingPathComponent(decoded)
            .standardizedFileURL.resolvingSymlinksInPath()
        let root = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard target.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") else { return nil }
        guard ["png", "jpg", "jpeg", "gif", "webp"].contains(target.pathExtension.lowercased()) else { return nil }
        return target
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        default: "image/png"
        }
    }
}
