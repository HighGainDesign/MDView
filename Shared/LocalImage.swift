import Foundation
import UniformTypeIdentifiers

enum LocalImage {
    /// Paths use the scoped handler; a protocol-relative network URL is not local.
    static func isLocalReference(_ source: String) -> Bool {
        pathReference(source) != nil
    }

    /// Convert a local file URL to a path without enabling network file hosts.
    /// Also used on Apex's image nodes before its safe HTML renderer runs.
    static func pathReference(_ source: String) -> String? {
        guard !source.isEmpty, !source.hasPrefix("//"),
              let components = URLComponents(string: source) else { return nil }
        guard let scheme = components.scheme else { return source }
        guard scheme.lowercased() == "file",
              components.host == nil || components.host == "" || components.host?.lowercased() == "localhost",
              components.user == nil, components.password == nil, components.port == nil,
              components.percentEncodedPath.hasPrefix("/") else { return nil }
        return components.percentEncodedPath
    }

    /// macOS file permissions govern access. Relative paths need a document base;
    /// absolute paths and local file URLs also work in in-memory previews.
    static func resolve(_ source: String, documentURL: URL?) -> URL? {
        guard let reference = pathReference(source) else { return nil }
        let path = reference.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
        guard let decoded = path.removingPercentEncoding else { return nil }
        let candidate: URL
        if decoded.hasPrefix("/") { candidate = URL(fileURLWithPath: decoded) }
        else if let documentURL { candidate = documentURL.deletingLastPathComponent().appendingPathComponent(decoded) }
        else { return nil }
        return candidate.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
