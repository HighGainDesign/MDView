import Foundation
import CryptoKit
import NaturalLanguage
import SwiftSoup

struct SpeechOptions: Codable, Equatable, Sendable {
    var includeCode = false
    var includeLinkDestinations = false
}

struct SpeechSegment: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case heading, paragraph, listItem, tableRow, code, image }
    let id: String
    let elementID: String
    let text: String
    let sectionID: String?
    let kind: Kind
}

struct SpeechSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let firstSegment: Int
}

struct SpeechDocument: Equatable, Sendable {
    let segments: [SpeechSegment]
    let sections: [SpeechSection]
    let language: String?
    let fingerprint: String

    func section(at segment: Int) -> SpeechSection? {
        sections.last { $0.firstSegment <= segment }
    }
}

/// Walk the already parsed, sanitized DOM once. Never re-parse Markdown or
/// derive spoken text from review decorations. QL does not request this work.
enum SpeechDocumentBuilder {
    static func prepare(_ document: Document, source: String, language: String?, options: SpeechOptions) throws -> SpeechDocument {
        try Builder(language: language, options: options).build(document, source: source)
    }

    private final class Builder {
        let language: String?
        let options: SpeechOptions
        var segments: [SpeechSegment] = []
        var sections: [SpeechSection] = []
        var nextElement = 0
        var sectionID: String?

        init(language: String?, options: SpeechOptions) { self.language = language; self.options = options }

        func build(_ document: Document, source: String) throws -> SpeechDocument {
            for child in document.body()?.children().array() ?? [] { try walk(child) }
            let fingerprint = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
            return SpeechDocument(segments: segments, sections: sections, language: language, fingerprint: fingerprint)
        }

        func walk(_ element: Element) throws {
            guard try element.attr("aria-hidden") != "true", !element.hasAttr("hidden") else { return }
            let tag = element.tagName()
            if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(tag) {
                let title = try inline(element)
                let id = try element.attr("id")
                sectionID = id.isEmpty ? "section-\(sections.count)" : id
                sections.append(SpeechSection(id: sectionID!, title: title, firstSegment: segments.count))
                try append(title, element: element, kind: .heading)
            } else if tag == "table" {
                try table(element)
            } else if tag == "pre" {
                let text = options.includeCode ? try element.text(trimAndNormaliseWhitespace: false) : label("code")
                try append(text, element: element, kind: .code)
            } else if tag == "li" {
                var text = try inline(element, skipLists: true)
                if let task = try element.select("input[type=checkbox]").array().first(where: { input in
                    var parent = input.parent()
                    while let current = parent {
                        if current.tagName() == "li" { return current === element }
                        parent = current.parent()
                    }
                    return false
                }) {
                    text = label(task.hasAttr("checked") ? "checked" : "unchecked") + ": " + text
                }
                try append(text, element: element, kind: .listItem)
                // Only lists directly owned by this item; deeper items visit theirs.
                for list in try element.select("ul,ol").array() {
                    var parent = list.parent()
                    while let current = parent, current !== element, !["ul", "ol", "li"].contains(current.tagName()) { parent = current.parent() }
                    if parent === element { for child in list.children().array() { try walk(child) } }
                }
            } else if ["p", "dt", "dd", "figcaption", "summary"].contains(tag) {
                try append(inline(element), element: element, kind: .paragraph)
            } else if tag == "img" {
                try append(inline(element), element: element, kind: .image)
            } else {
                for child in element.children().array() { try walk(child) }
            }
        }

        func table(_ table: Element) throws {
            let rows = try table.select("tr").array().filter { row in
                var parent = row.parent()
                while let current = parent { if current.tagName() == "table" { return current === table }; parent = current.parent() }
                return false
            }
            let firstCells = rows.first?.children().array() ?? []
            let hasHeaders = !firstCells.isEmpty && firstCells.allSatisfy { $0.tagName() == "th" }
            let headers = hasHeaders ? try firstCells.map { try inline($0) } : []
            for (index, row) in rows.enumerated() {
                if index == 0 && hasHeaders && rows.count > 1 { continue }
                let cells = try row.children().array().map { try inline($0) }
                let values = cells.enumerated().map { column, value in
                    !headers.isEmpty && index > 0 && column < headers.count && !headers[column].isEmpty
                        ? "\(headers[column]): \(value)" : value
                }
                try append(values.joined(separator: "; "), element: row, kind: .tableRow)
            }
        }

        func inline(_ node: Node, skipLists: Bool = false) throws -> String {
            if let text = node as? TextNode { return text.getWholeText() }
            guard let element = node as? Element else { return "" }
            let tag = element.tagName()
            if try element.attr("aria-hidden") == "true" || element.hasAttr("hidden") { return "" }
            if skipLists && ["ul", "ol"].contains(tag) { return "" }
            if tag == "input" { return "" }
            if tag == "img" { return try element.attr("alt") }
            if tag == "br" { return " " }
            let role = try element.attr("role")
            let classes = try element.attr("class").split(separator: " ")
            if role == "doc-backlink" || role == "doc-noteref" ||
                classes.contains(where: { ["footnote-backref", "reversefootnote", "footnote-ref"].contains(String($0)) }) { return "" }
            let text = try element.getChildNodes().map { try inline($0, skipLists: skipLists) }.joined()
            if tag == "a" && options.includeLinkDestinations, let href = try? element.attr("href"), !href.isEmpty, !href.hasPrefix("#") {
                return text == href ? text : text + " (" + href + ")"
            }
            return text
        }

        func append(_ raw: String, element: Element, kind: SpeechSegment.Kind) throws {
            let text = kind == .code && options.includeCode ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
                : raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { return }
            let elementID = "speech-\(nextElement)"; nextElement += 1
            try element.attr("data-mdview-speech", elementID)
            for (index, chunk) in Self.chunks(text).enumerated() {
                segments.append(SpeechSegment(id: "\(elementID)-\(index)", elementID: elementID,
                    text: chunk, sectionID: sectionID, kind: kind))
            }
        }

        static func chunks(_ text: String) -> [String] {
            var chunks: [String] = [], current = "", count = 0
            let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
            var cursor = text.startIndex
            func consume(_ unit: Substring) {
                if count + unit.utf16.count > 1200 && !current.isEmpty {
                    chunks.append(current); current = ""; count = 0
                }
                for character in unit {
                    let value = String(character), size = value.utf16.count
                    if count + size > 1200 && !current.isEmpty {
                        chunks.append(current); current = ""; count = 0
                    }
                    current += value; count += size
                }
            }
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                // Carry whitespace between sentence tokens, preserving exact
                // Unicode text while preferring a natural utterance boundary.
                consume(text[cursor..<range.upperBound]); cursor = range.upperBound
                return true
            }
            if cursor < text.endIndex { consume(text[cursor..<text.endIndex]) }
            if !current.isEmpty { chunks.append(current) }
            return chunks
        }

        func label(_ key: String) -> String {
            // These short semantic cues follow document language, not UI locale.
            let base = language?.split(separator: "-").first.map(String.init) ?? "en"
            let labels = [
                "en": ["checked": "Checked", "unchecked": "Unchecked", "code": "Code block omitted"],
                "es": ["checked": "Completado", "unchecked": "Pendiente", "code": "Bloque de código omitido"],
                "zh": ["checked": "已完成", "unchecked": "未完成", "code": "略过代码块"],
                "ja": ["checked": "完了", "unchecked": "未完了", "code": "コードブロックを省略"],
                "fr": ["checked": "Terminé", "unchecked": "À faire", "code": "Bloc de code omis"],
                "de": ["checked": "Erledigt", "unchecked": "Offen", "code": "Codeblock ausgelassen"]
            ]
            return labels[base]?[key] ?? labels["en"]![key]!
        }
    }
}
