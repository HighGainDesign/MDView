import Foundation
import SwiftSoup

struct DocumentChange: Identifiable, Sendable {
    enum Kind: String, Sendable { case added = "Added", edited = "Edited", removed = "Removed" }
    let id: Int
    let kind: Kind
    let targetID: String?
    let before: String
    let after: String
}

struct ChangeSummary: Sendable {
    var entries: [DocumentChange] = []
    var usesSectionComparison = false
    var count: Int { entries.count }
    var navigable: [DocumentChange] { entries.filter { $0.targetID != nil } }
}

/// Compares rendered reading units, so Markdown formatting and links remain
/// intact. Swift's CollectionDifference aligns unchanged blocks and words.
/// Deleted text belongs in the review summary rather than in the current file.
enum DocumentChanges {
    private static let selector = "h1, h2, h3, h4, h5, h6, p, li, pre, th, td, dt, dd, figure"
    private static let unitTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "pre", "th", "td", "dt", "dd", "figure"]

    static func annotate(current: Document, baseline: Document) throws -> ChangeSummary {
        let old = try units(in: baseline)
        let new = try units(in: current)
        let oldKeys = try old.map { try $0.tagName() + "|" + $0.attr("align") + "|" + $0.html() }
        let newKeys = try new.map { try $0.tagName() + "|" + $0.attr("align") + "|" + $0.html() }
        guard oldKeys != newKeys else { return ChangeSummary() }
        // Bound worst-case sequence work for huge generated documents. The
        // fallback is explicit in the review panel and preserves every block.
        let coarse = max(old.count, new.count) > 2_500
        var removed: Set<Int> = [], inserted: Set<Int> = []
        if coarse {
            for i in 0..<max(old.count, new.count) {
                if i < old.count, i < new.count, oldKeys[i] == newKeys[i] { continue }
                if i < old.count { removed.insert(i) }
                if i < new.count { inserted.insert(i) }
            }
        } else {
            for change in newKeys.difference(from: oldKeys) {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
        }
        var summary = ChangeSummary(usesSectionComparison: coarse)
        var oldIndex = 0, newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            var oldRun: [Element] = [], newRun: [Element] = []
            while oldIndex < old.count, removed.contains(oldIndex) { oldRun.append(old[oldIndex]); oldIndex += 1 }
            while newIndex < new.count, inserted.contains(newIndex) { newRun.append(new[newIndex]); newIndex += 1 }
            if !oldRun.isEmpty || !newRun.isEmpty {
                for i in 0..<max(oldRun.count, newRun.count) {
                    let previous = i < oldRun.count ? oldRun[i] : nil
                    let updated = i < newRun.count ? newRun[i] : nil
                    let before = try previous?.text() ?? ""
                    let after = try updated?.text() ?? ""
                    let kind: DocumentChange.Kind = previous == nil ? .added : (updated == nil ? .removed : .edited)
                    let index = summary.entries.count
                    var target: String?
                    if let updated {
                        try updated.addClass("mdview-change")
                        try updated.addClass(kind == .added ? "mdview-added" : "mdview-edited")
                        target = try updated.attr("id")
                        if target?.isEmpty != false {
                            target = "mdview-change-\(index)"
                            try updated.attr("id", target!)
                        }
                        try updated.attr("aria-description", kind.rawValue + " since last review")
                        if let previous { try highlightWords(in: updated, comparedWith: previous) }
                    }
                    summary.entries.append(DocumentChange(id: index, kind: kind, targetID: target, before: before, after: after))
                }
            } else {
                oldIndex += 1
                newIndex += 1
            }
        }
        return summary
    }

    private static func units(in document: Document) throws -> [Element] {
        try document.select(selector).array().filter { element in
            var ancestor = element.parent()
            while let parent = ancestor {
                if unitTags.contains(parent.tagName()) { return false }
                ancestor = parent.parent()
            }
            return true
        }
    }

    private static func textNodes(in node: Node) -> [TextNode] {
        if let text = node as? TextNode { return [text] }
        return node.getChildNodes().flatMap { textNodes(in: $0) }
    }

    private static func highlightWords(in element: Element, comparedWith previous: Element) throws {
        let nodes = textNodes(in: element)
        let newText = nodes.map { $0.getWholeText() }.joined()
        let oldText = textNodes(in: previous).map { $0.getWholeText() }.joined()
        let expression = try NSRegularExpression(pattern: "\\s+|[^\\s]+")
        let newMatches = expression.matches(in: newText, range: NSRange(newText.startIndex..., in: newText))
        let oldMatches = expression.matches(in: oldText, range: NSRange(oldText.startIndex..., in: oldText))
        guard max(newMatches.count, oldMatches.count) <= 2_000 else { return }
        let newWords = newMatches.map { (newText as NSString).substring(with: $0.range) }
        let oldWords = oldMatches.map { (oldText as NSString).substring(with: $0.range) }
        let ranges = newWords.difference(from: oldWords).compactMap { change -> NSRange? in
            if case .insert(let offset, _, _) = change, !newWords[offset].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return newMatches[offset].range
            }
            return nil
        }.sorted { $0.location < $1.location }
        var location = 0
        for node in nodes {
            let text = node.getWholeText() as NSString
            let nodeRange = NSRange(location: location, length: text.length)
            let intersections = ranges.map { NSIntersectionRange(nodeRange, $0) }.filter { $0.length > 0 }
            location += text.length
            guard !intersections.isEmpty else { continue }
            var cursor = 0
            for range in intersections {
                let local = NSRange(location: range.location - nodeRange.location, length: range.length)
                if local.location > cursor {
                    try node.before(TextNode(text.substring(with: NSRange(location: cursor, length: local.location - cursor)), ""))
                }
                let mark = Element(try Tag.valueOf("mark"), "")
                try mark.addClass("mdview-word-change")
                try mark.text(text.substring(with: local))
                try node.before(mark)
                cursor = local.location + local.length
            }
            if cursor < text.length { try node.before(TextNode(text.substring(from: cursor), "")) }
            try node.remove()
        }
    }
}
