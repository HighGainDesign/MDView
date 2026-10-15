import AppKit

/// One queue per reader. Only the current reader may request speech; routine
/// updates use medium priority so VoiceOver can finish its current utterance.
@MainActor
final class ReaderAnnouncements {
    enum Topic: Int {
        case failure, saveFailure, refreshFailure, imageFailure, streamFailure
        case review, updates, changes, search, navigation
    }
    var suppressRoutine = false {
        didSet {
            if suppressRoutine { for topic in [Topic.review, .updates, .changes] { cancel(topic: topic) } }
        }
    }
    var isEligible: () -> Bool = { false }
    private let delay: Duration
    private let post: (String) -> Void
    private var pending: [Topic: String] = [:]
    private var delivery: Task<Void, Never>?
    private var generation = 0

    init(delay: Duration = .milliseconds(400), post: @escaping (String) -> Void = { message in
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }) {
        self.delay = delay
        self.post = post
    }

    func schedule(_ message: String, topic: Topic) {
        guard isEligible(), !message.isEmpty else { return }
        if suppressRoutine && [Topic.review, .updates, .changes].contains(topic) { return }
        if topic == .review { pending.removeValue(forKey: .changes) }
        pending[topic] = String(message.prefix(500))
        guard delivery == nil else { return }
        generation += 1
        let current = generation, delay = delay
        delivery = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, generation == current else { return }
            let messages = pending.sorted { $0.key.rawValue < $1.key.rawValue }.prefix(3).map(\.value)
            pending.removeAll()
            delivery = nil
            guard isEligible(), !messages.isEmpty else { return }
            post(messages.joined(separator: "\n"))
        }
    }

    func cancel(topic: Topic) {
        pending.removeValue(forKey: topic)
        if pending.isEmpty { cancel() }
    }

    func cancel() {
        generation += 1
        delivery?.cancel()
        delivery = nil
        pending.removeAll()
    }
}
