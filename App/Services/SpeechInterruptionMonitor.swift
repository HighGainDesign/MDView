import AppKit
@preconcurrency import CoreAudio

/// macOS has no AVAudioSession. Observe the default output and sleep directly;
/// a route change pauses for privacy instead of unexpectedly using speakers.
@MainActor
final class SpeechInterruptionMonitor {
    private let interrupted: (String) -> Void
    private var sleepObserver: NSObjectProtocol?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    init(interrupted: @escaping (String) -> Void) { self.interrupted = interrupted }
    func start() {
        stop()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.interrupted(String(localized: "Reading paused while the Mac sleeps.")) }
            }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.interrupted(String(localized: "Audio output changed. Resume reading when you are ready.")) }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            outputListener = listener
        }
    }
    func stop() {
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver); self.sleepObserver = nil }
        if let outputListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, outputListener)
            self.outputListener = nil
        }
    }
}
