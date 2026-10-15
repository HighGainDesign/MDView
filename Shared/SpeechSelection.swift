import Foundation

struct SpeechPosition: Equatable, Sendable { let index: Int; let offset: Int }
struct SpeechAnchor: Equatable, Sendable {
    let sourceRange: NSRange
    let sourceText: String
    let spokenOffset: Int
    let literal: Bool
}
struct SpeechElementMap: Equatable, Sendable {
    let sourceLength: Int
    let anchors: [SpeechAnchor]
}

extension SpeechDocument {
    /// Offsets are measured in the element's textContent, which remains stable
    /// when change review wraps words in marks. No fragile DOM-node paths.
    func position(elementID: String, sourceOffset: Int) -> SpeechPosition? {
        guard let map = elements[elementID], sourceOffset >= 0, sourceOffset <= map.sourceLength,
              let first = segments.firstIndex(where: { $0.elementID == elementID }) else { return nil }
        guard let anchor = map.anchors.first(where: { NSLocationInRange(sourceOffset, $0.sourceRange) })
                ?? map.anchors.first(where: { $0.sourceRange.location >= sourceOffset }) ?? map.anchors.last else {
            return SpeechPosition(index: first, offset: 0)
        }
        let raw = anchor.sourceText as NSString
        var local = min(raw.length, max(0, sourceOffset - anchor.sourceRange.location))
        if local < raw.length { local = raw.rangeOfComposedCharacterSequence(at: local).location }
        let prefix = raw.substring(to: local)
        let inside: Int
        if anchor.literal { inside = local }
        else {
            let normalized = prefix.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let trailing = !normalized.isEmpty && prefix.last?.isWhitespace == true ? 1 : 0
            inside = min(normalized.utf16.count + trailing,
                         anchor.sourceText.split(whereSeparator: \.isWhitespace).joined(separator: " ").utf16.count)
        }
        let absolute = anchor.spokenOffset + inside
        let matches = segments.indices.filter { segments[$0].elementID == elementID }
        let index = matches.last(where: { segments[$0].elementOffset <= absolute }) ?? first
        return SpeechPosition(index: index, offset: min(segments[index].text.utf16.count, max(0, absolute - segments[index].elementOffset)))
    }
}
