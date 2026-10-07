import AppKit

/// Receives the public Marked-compatible channel. Never use the general clipboard.
@MainActor
struct MarkdownStream {
    static let name = NSPasteboard.Name("mkStreamingPreview")
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = NSPasteboard(name: name)) {
        self.pasteboard = pasteboard
    }

    enum Update: Equatable {
        case waiting
        case text(String, source: String?)
    }

    func read(after changeCount: Int?) throws -> (count: Int, update: Update)? {
        let count = pasteboard.changeCount
        guard count != changeCount else { return nil }
        guard let data = pasteboard.data(forType: .string) else { return (count, .waiting) }
        guard data.count <= MarkdownSource.maximumBytes else { throw ReaderError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ReaderError.invalidEncoding }
        // Source metadata is optional in the public protocol. Unattributed
        // Markdown is valid too; don't mistake an ordinary HTML comment for metadata.
        if text.hasPrefix("<!--"), let end = text.range(of: "-->"),
           text.distance(from: text.startIndex, to: end.upperBound) <= 512 {
            let metadata = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in metadata.split(separator: "\n") {
                let field = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard field.hasPrefix("source:"),
                      let source = Self.sourceName(String(field.dropFirst(7))) else { continue }
                let markdown = String(text[end.upperBound...].drop(while: { $0 == "\n" || $0 == "\r" }))
                return (count, .text(markdown, source: source))
            }
        }
        return (count, .text(text, source: nil))
    }

    private static func sourceName(_ value: String) -> String? {
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty, identifier.count <= 128,
              identifier.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        // A source may be an app name or a bundle identifier. This only resolves
        // installed app metadata; it neither launches the app nor grants access.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                       ?? bundle.object(forInfoDictionaryKey: "CFBundleName")) as? String,
           !name.isEmpty, name.count <= 128,
           name.rangeOfCharacter(from: .controlCharacters) == nil {
            return name
        }
        let name = (identifier as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
