import Foundation
import Observation

/// The document owns this controller, while the session owns immutable speech.
/// Receiving new source remains independent from applying it to the page.
@MainActor @Observable
final class ReaderSpeech {
    let session: SpeechSession
    let preferences: SpeechPreferences
    private(set) var isHolding = false
    var showPlayer = false
    private(set) var message: String?
    @ObservationIgnored private weak var reader: ReaderState?
    @ObservationIgnored private let progress: SpeechProgressStore
    @ObservationIgnored private var playbackURL: URL?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var latestTask: Task<Void, Never>?

    init(reader: ReaderState, session: SpeechSession = SpeechSession(),
         preferences: SpeechPreferences = .shared, progress: SpeechProgressStore = SpeechProgressStore()) {
        self.reader = reader; self.session = session; self.preferences = preferences; self.progress = progress
        session.onProgress = { [weak self] in self?.didProgress() }
        session.onStop = { [weak self] in
            guard let self else { return }
            checkpoint(force: true)
            self.reader?.announcements.suppressRoutine = false
            if self.reader?.hasPendingFileUpdate != true { isHolding = false }
        }
    }

    var bookmark: SpeechBookmark? {
        guard let reader, let url = reader.fileURL, let document = reader.rendered?.speech else { return nil }
        return progress.resume(url: url, document: document)
    }

    func start(at index: Int = 0, offset: Int = 0) {
        latestTask?.cancel(); latestTask = nil
        showPlayer = true; message = nil
        if reader?.showChecklistConfirmation == true {
            message = String(localized: "Finish the checklist confirmation before starting Read Aloud."); return
        }
        guard let reader, !reader.isRendering, !reader.checklistSaving,
              let output = reader.rendered, output.taskSource == reader.source, let document = output.speech else {
            message = String(localized: "Wait for the document to finish loading, then try Read Aloud again."); return
        }
        playbackURL = reader.isStreamingPreview ? nil : reader.fileURL
        isHolding = true
        session.followReading = preferences.followReading
        session.setRate(preferences.rate)
        session.setVoice(preferences.voice(for: document.language))
        session.play(document, from: index, offset: offset)
    }
    func resumeSaved() {
        if let bookmark { start(at: bookmark.index, offset: bookmark.offset) }
        else { start() }
    }
    func togglePlayback() {
        switch session.status {
        case .playing: session.pause()
        case .paused: session.resume()
        default: resumeSaved()
        }
    }
    func stop() { latestTask?.cancel(); latestTask = nil; session.stop() }
    func close() { stop(); isHolding = false; showPlayer = false }
    func showLatest(read: Bool = false) {
        let oldSection = session.document?.section(at: session.currentIndex)?.id
        stop(); isHolding = false
        guard let reader else { return }
        reader.applyPendingPlaybackVersion()
        guard read else { return }
        latestTask = Task { [weak self, weak reader] in
            guard let self, let reader else { return }
            while reader.isRendering {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let index = reader.rendered?.speech?.sections.first(where: { $0.id == oldSection })?.firstSegment ?? 0
            start(at: index)
        }
    }
    func setRate(_ rate: Double) { preferences.rate = rate; session.setRate(preferences.rate) }
    func setVoice(_ id: String?) {
        preferences.setVoice(id, for: session.document?.language ?? reader?.rendered?.documentLanguage)
        session.setVoice(id)
    }
    func setFollowReading(_ follow: Bool) { preferences.followReading = follow; session.followReading = follow }
    func clearHistory() { progress.clear() }

    private func didProgress() {
        reader?.announcements.suppressRoutine = session.isActive
        if session.isActive { checkpoint(force: session.status == .paused) }
    }
    private func checkpoint(force: Bool) {
        guard force || Date().timeIntervalSince(lastCheckpoint) >= 2,
              let playbackURL, let document = session.document else { return }
        progress.save(url: playbackURL, document: document, index: session.currentIndex, offset: session.offset)
        lastCheckpoint = Date()
    }
}
