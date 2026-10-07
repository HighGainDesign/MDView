import ApexC
import Foundation
import SwiftSoup

struct MarkdownHeading: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let level: Int
}

struct RenderedMarkdown: Sendable {
    let html: String
    let headings: [MarkdownHeading]
    let wordCount: Int
    var changes = ChangeSummary()
}

/// Serializes native Apex conversions off the UI actor. App and Quick Look use
/// the same options, HTML adaptation, and bundled CSS. No AppKit dependency.
actor MarkdownRenderer {
    static let shared = MarkdownRenderer()
    private var stylesheet: String?

    func render(_ source: String, title: String = "Markdown", wide: Bool = false, baseline: String? = nil, loadRemoteImages: Bool = false, appearance: DocumentAppearance = .system) throws -> RenderedMarkdown {
        guard source.utf8.count <= MarkdownSource.maximumBytes else { throw ReaderError.tooLarge }
        if stylesheet == nil {
            guard let cssURL = Bundle(for: RendererBundleMarker.self).url(forResource: "reader", withExtension: "css") else {
                throw ReaderError.rendererUnavailable
            }
            stylesheet = try String(contentsOf: cssURL, encoding: .utf8)
        }
        let document = try parse(source, loadRemoteImages: loadRemoteImages)
        let headings = try document.select("h1, h2, h3, h4, h5, h6").array().map { heading in
            MarkdownHeading(id: try heading.attr("id"), title: try heading.text(),
                            level: Int(heading.tagName().dropFirst()) ?? 1)
        }
        var changes = ChangeSummary()
        if let baseline, baseline != source {
            changes = try DocumentChanges.annotate(current: document, baseline: parse(baseline, loadRemoteImages: loadRemoteImages))
        }
        let body = try document.body()?.html() ?? ""
        let count = source.split(whereSeparator: \.isWhitespace).count
        let html = """
        <!doctype html><html lang="en" data-appearance="\(appearance.rawValue)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <meta name="color-scheme" content="\(appearance.colorScheme)">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src mdview-resource: data:\(loadRemoteImages ? " https:" : ""); base-uri 'none'; form-action 'none'">
        <title>\(Self.escapeHTML(title))</title><style>\(stylesheet ?? "")</style></head>
        <body class="\(wide ? "wide" : "")"><main id="document" aria-label="Markdown document">\(body)</main></body></html>
        """
        return RenderedMarkdown(html: html, headings: headings, wordCount: count, changes: changes)
    }

    private func parse(_ source: String, loadRemoteImages: Bool) throws -> Document {
        guard source.utf8.count <= MarkdownSource.maximumBytes else { throw ReaderError.tooLarge }
        var options = apex_options_for_mode(APEX_MODE_UNIFIED)
        // The C API makes false values explicit; the Swift wrapper only forwards
        // true boolean options, whereas unified mode defaults to unsafe HTML.
        options.unsafe = false
        options.enable_plugins = false
        options.allow_external_plugin_detection = false
        options.enable_file_includes = false
        options.enable_metadata_transforms = false
        options.enable_attributes = false
        options.enable_markdown_in_html = false
        options.enable_smart_typography = false
        options.enable_math = false
        options.enable_citations = false
        // Apex's styled callouts use internal raw HTML, which safe mode omits.
        // Preserve their source as readable blockquotes instead.
        options.enable_callouts = false
        options.embed_images = false
        options.enable_autolink = true
        options.enable_aria = true
        options.id_format = 0
        options.github_pre_lang = false
        options.generate_header_ids = true
        let fragment = try source.withCString { markdown in
            guard let output = apex_markdown_to_html(markdown, source.utf8.count, &options) else {
                throw ReaderError.rendererUnavailable
            }
            defer { apex_free_string(output) }
            return String(cString: output)
        }
        let document = try SwiftSoup.parseBodyFragment(fragment)
        document.outputSettings().prettyPrint(pretty: false)
        try HTMLAdapter.prepare(document, loadRemoteImages: loadRemoteImages)
        return document
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class RendererBundleMarker: NSObject {}
