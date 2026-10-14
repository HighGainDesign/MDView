import Foundation
import NaturalLanguage

/// Document language is independent of the interface locale and future voice
/// preferences. Unknown short/code-heavy content must not be labeled English.
enum DocumentLanguage {
    private static let registered = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))
    static let menuCodes = ["ar", "bn", "zh-Hans", "zh-Hant", "cs", "da", "nl", "en", "fi", "fr", "de", "el", "he", "hi", "id", "it", "ja", "ko", "ms", "no", "fa", "pl", "pt", "ru", "es", "sv", "ta", "te", "th", "tr", "uk", "vi"]

    static func normalized(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        guard candidate.range(of: #"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{1,8})*$"#, options: .regularExpression) != nil else { return nil }
        let canonical = Locale.canonicalLanguageIdentifier(from: candidate)
        guard let base = canonical.split(separator: "-").first, registered.contains(String(base)) else { return nil }
        return canonical
    }

    static func resolve(selected: String?, text: String) -> String? {
        if let selected, let known = normalized(selected) { return known }
        let sample = String(text.prefix(8_000))
        guard sample.filter(\.isLetter).count >= 80 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first,
              best.value >= 0.8 else { return nil }
        return normalized(best.key.rawValue)
    }

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
