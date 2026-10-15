import Foundation
import Observation

/// The document owns this controller, while the session owns immutable speech.
/// Receiving new source remains independent from applying it to the page.
@MainActor @Observable
final class ReaderSpeech {
    enum StartMode: String { case beginning, visible, selection }
    struct StartRequest: Equatable { let id: UUID; let mode: StartMode; let fingerprint: String }
    private(set) var startRequest: StartRequest?
    let session: SpeechSession
    let preferences: SpeechPreferences
    private(set) var isHolding = false
    var showPlayer = false { didSet { if showPlayer && !oldValue { session.refreshVoices() } } }
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
        _ = preferences.historyRevision
        guard let reader, let url = reader.fileURL, let document = reader.rendered?.speech else { return nil }
        return progress.resume(url: url, document: document)
    }

    func start(at index: Int = 0, offset: Int = 0) {
        latestTask?.cancel(); latestTask = nil; startRequest = nil
        showPlayer = true; message = nil
        if reader?.showChecklistConfirmation == true {
            message = String(localized: "Finish the checklist confirmation before starting Read Aloud."); return
        }
        guard let reader, !reader.isRendering, !reader.checklistSaving,
              let output = reader.rendered, output.taskSource == reader.source, let document = output.speech else {
            message = String(localized: "Wait for the document to finish loading, then try Read Aloud again."); return
        }
        if prepareOptionsIfNeeded({ $0.start(at: index, offset: offset) }) { return }
        if session.isActive { session.stop() }
        playbackURL = reader.isStreamingPreview ? nil : reader.fileURL
        isHolding = true
        session.useAssistiveTechnologySettings = preferences.useAssistiveTechnologySettings
        session.followReading = preferences.followReading
        session.setRate(preferences.rate)
        session.setVoice(preferences.voice(for: document.language))
        session.play(document, from: index, offset: offset)
    }
    func requestStart(_ mode: StartMode) {
        latestTask?.cancel(); latestTask = nil
        if mode == .beginning { start(); return }
        showPlayer = true; message = nil
        guard let reader, !reader.isRendering, let document = reader.rendered?.speech else {
            message = String(localized: "Wait for the document to finish loading, then try Read Aloud again."); return
        }
        if prepareOptionsIfNeeded({ $0.requestStart(mode) }) { return }
        startRequest = StartRequest(id: UUID(), mode: mode, fingerprint: document.fingerprint)
    }
    func completeStart(_ request: StartRequest, elementID: String?, offset: Int) {
        guard startRequest?.id == request.id, let reader,
              let document = reader.rendered?.speech, document.fingerprint == request.fingerprint else { return }
        startRequest = nil
        if document.options != preferences.options { requestStart(request.mode); return }
        guard let elementID else {
            message = String(localized: "Select text in the document to choose where reading starts."); return
        }
        if request.mode == .visible, let index = document.segments.firstIndex(where: { $0.elementID == elementID }) {
            start(at: document.section(at: index)?.firstSegment ?? index)
        } else if let position = document.position(elementID: elementID, sourceOffset: offset) {
            start(at: position.index, offset: position.offset)
        } else { message = String(localized: "That selection is no longer available. Select the text again.") }
    }

    func resumeSaved() {
        if prepareOptionsIfNeeded({ $0.resumeSaved() }) { return }
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
    func stop() { latestTask?.cancel(); latestTask = nil; startRequest = nil; session.stop() }
    func close(discardHold: Bool = false) {
        stop(); showPlayer = false
        // Closing playback controls must not hide a pending-version decision.
        // Only a document closing/switching may discard its display hold.
        if discardHold { isHolding = false }
    }
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
    func clearHistory() { progress.clear(); preferences.historyRevision += 1 }

    /// Content choices affect preparation, never an utterance already in flight.
    /// Queue the original intent after a fresh render; Stop/close cancels it.
    private func prepareOptionsIfNeeded(_ resume: @escaping @MainActor (ReaderSpeech) -> Void) -> Bool {
        guard let reader, let document = reader.rendered?.speech, document.options != preferences.options else { return false }
        latestTask?.cancel(); startRequest = nil
        if session.isActive { session.stop() }
        let source = reader.source
        reader.render()
        latestTask = Task { [weak self, weak reader] in
            guard let self, let reader else { return }
            while reader.isRendering {
                do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            }
            guard !Task.isCancelled, reader.source == source,
                  reader.rendered?.speech?.options == preferences.options else { return }
            resume(self)
        }
        return true
    }

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
