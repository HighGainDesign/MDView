import Foundation

enum StartupTips {
    private static let suppressionKey = "hideStartupTips"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: suppressionKey)
    }

    static func finish(dontShowAgain: Bool, defaults: UserDefaults = .standard) {
        defaults.set(dontShowAgain, forKey: suppressionKey)
    }
}
