import Foundation
@preconcurrency import AVFAudio

struct SpeechVoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let language: String
    let quality: Int
}

enum SpeechDriverEvent: Sendable {
    case started(UUID), finished(UUID), cancelled(UUID), failed(UUID, String)
    case range(UUID, NSRange), interrupted(UUID, String), voicesChanged(UUID)
}

@MainActor
protocol SpeechDriver: AnyObject {
    var eventHandler: ((SpeechDriverEvent) -> Void)? { get set }
    var useAssistiveTechnologySettings: Bool { get set }
    func speak(_ text: String, voice: SpeechVoice?, rate: Double, token: UUID)
    func pause() -> Bool
    func resume() -> Bool
    func stop()
}

/// Only this adapter touches the system synthesizer. The state machine can be
/// tested without generating sound, requesting permissions or changing voices.
@MainActor
final class SystemSpeechDriver: NSObject, SpeechDriver, AVSpeechSynthesizerDelegate {
    var eventHandler: ((SpeechDriverEvent) -> Void)?
    var useAssistiveTechnologySettings = false
    private let synthesizer = AVSpeechSynthesizer()
    private var voiceObserver: NSObjectProtocol?
    private var active: (utterance: ObjectIdentifier, token: UUID)?
    private lazy var interruptions = SpeechInterruptionMonitor { [weak self] message in
        guard let self, let active else { return }
        eventHandler?(.interrupted(active.token, message))
    }

    override init() { super.init(); synthesizer.delegate = self }

    static func availableVoices() -> [SpeechVoice] {
        let defaultID = AVSpeechSynthesisVoice(language: nil)?.identifier
        return AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
        }.map { SpeechVoice(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue) }.sorted {
            if ($0.id == defaultID) != ($1.id == defaultID) { return $0.id == defaultID }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func speak(_ text: String, voice: SpeechVoice?, rate: Double, token: UUID) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        utterance.prefersAssistiveTechnologySettings = useAssistiveTechnologySettings
        active = (ObjectIdentifier(utterance), token)
        voiceObserver = NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.eventHandler?(.voicesChanged(token)) }
            }
        interruptions.start()
        synthesizer.speak(utterance)
    }
    func pause() -> Bool { synthesizer.pauseSpeaking(at: .word) }
    func resume() -> Bool { synthesizer.continueSpeaking() }
    func stop() {
        active = nil; synthesizer.stopSpeaking(at: .immediate); interruptions.stop()
        if let voiceObserver { NotificationCenter.default.removeObserver(voiceObserver); self.voiceObserver = nil }
    }

    private func deliver(_ identity: ObjectIdentifier, makeEvent: (UUID) -> SpeechDriverEvent, complete: Bool = false) {
        guard let active, active.utterance == identity else { return }
        if complete { self.active = nil }
        eventHandler?(makeEvent(active.token))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.deliver(identity, makeEvent: SpeechDriverEvent.started) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.deliver(identity, makeEvent: SpeechDriverEvent.finished, complete: true) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.deliver(identity, makeEvent: SpeechDriverEvent.cancelled, complete: true) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.deliver(identity, makeEvent: { .range($0, characterRange) }) }
    }
}
