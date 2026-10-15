import Foundation
import Observation

@MainActor @Observable
final class SpeechPreferences {
    static let shared = SpeechPreferences()
    @ObservationIgnored private let defaults: UserDefaults
    private var storedRate: Double
    var rate: Double {
        get { storedRate }
        set {
            storedRate = Self.validRate(newValue)
            defaults.set(storedRate, forKey: "speechRate")
        }
    }
    var followReading: Bool { didSet { defaults.set(followReading, forKey: "speechFollowReading") } }
    var useAssistiveTechnologySettings: Bool { didSet { defaults.set(useAssistiveTechnologySettings, forKey: "speechUseAssistiveSettings") } }
    var options: SpeechOptions {
        didSet { if let data = try? JSONEncoder().encode(options) { defaults.set(data, forKey: "speechOptions") } }
    }
    var historyRevision = 0
    private var voiceIDs: [String: String]

    init(defaults: UserDefaults = ReaderPreferences.defaults) {
        self.defaults = defaults
        storedRate = Self.validRate(defaults.object(forKey: "speechRate") as? Double ?? 1)
        followReading = defaults.object(forKey: "speechFollowReading") as? Bool ?? true
        useAssistiveTechnologySettings = defaults.bool(forKey: "speechUseAssistiveSettings")
        if let data = defaults.data(forKey: "speechOptions"), data.count < 1024,
           let saved = try? JSONDecoder().decode(SpeechOptions.self, from: data) { options = saved }
        else { options = SpeechOptions() }
        voiceIDs = defaults.dictionary(forKey: "speechVoices") as? [String: String] ?? [:]
    }
    func voice(for language: String?) -> String? {
        let language = key(language)
        return voiceIDs[language] ?? voiceIDs[language.split(separator: "-").first.map(String.init) ?? language]
    }
    func setVoice(_ id: String?, for language: String?) {
        voiceIDs[key(language)] = id
        defaults.set(voiceIDs, forKey: "speechVoices")
    }
    private func key(_ language: String?) -> String { language.flatMap(DocumentLanguage.normalized) ?? "automatic" }
    private static func validRate(_ value: Double) -> Double { value.isFinite ? (min(2, max(0.5, value)) * 100).rounded() / 100 : 1 }
}
