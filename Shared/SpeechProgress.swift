import Foundation
import CryptoKit

struct SpeechBookmark: Codable, Equatable, Sendable {
    let fingerprint: String
    let segmentHash: String
    let index: Int
    let offset: Int
    let sequence: Int
}

/// Bounded local hashes and locations only: never stores document text or paths.
@MainActor
final class SpeechProgressStore {
    private let defaults: UserDefaults
    private let key = "speechReadingProgress"
    init(defaults: UserDefaults = ReaderPreferences.defaults) { self.defaults = defaults }

    func save(url: URL, document: SpeechDocument, index: Int, offset: Int) {
        guard document.segments.indices.contains(index) else { return }
        var entries = read()
        let sequence = (entries.values.map(\.sequence).max() ?? 0) + 1
        entries[identity(url)] = SpeechBookmark(fingerprint: document.fingerprint,
            segmentHash: hash(document.segments[index].text), index: index,
            offset: min(max(0, offset), document.segments[index].text.utf16.count), sequence: sequence)
        for pair in entries.sorted(by: { $0.value.sequence > $1.value.sequence }).dropFirst(100) { entries.removeValue(forKey: pair.key) }
        if let encoded = try? JSONEncoder().encode(entries) { defaults.set(encoded, forKey: key) }
    }
    func resume(url: URL, document: SpeechDocument) -> SpeechBookmark? {
        guard let saved = read()[identity(url)] else { return nil }
        let index: Int
        if saved.fingerprint == document.fingerprint && document.segments.indices.contains(saved.index) &&
            hash(document.segments[saved.index].text) == saved.segmentHash { index = saved.index }
        else {
            let matches = document.segments.indices.filter { hash(document.segments[$0].text) == saved.segmentHash }
            guard matches.count == 1, let matched = matches.first else { return nil }
            index = matched
        }
        if index == document.segments.count - 1 && saved.offset >= document.segments[index].text.utf16.count { return nil }
        return SpeechBookmark(fingerprint: document.fingerprint, segmentHash: saved.segmentHash, index: index,
            offset: min(max(0, saved.offset), document.segments[index].text.utf16.count), sequence: saved.sequence)
    }
    func clear() { defaults.removeObject(forKey: key) }
    private func read() -> [String: SpeechBookmark] {
        guard let data = defaults.data(forKey: key), data.count < 100_000,
              let decoded = try? JSONDecoder().decode([String: SpeechBookmark].self, from: data) else { return [:] }
        return decoded
    }
    private func identity(_ url: URL) -> String { hash(url.standardizedFileURL.resolvingSymlinksInPath().path) }
    private func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
