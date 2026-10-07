import AppKit

@MainActor
enum QuickLookSettings {
    static func open() {
        // macOS 15 moved extension controls to General. The URL opens the
        // containing pane; category selection remains under the user's control.
        let address: String
        if #available(macOS 15, *) {
            address = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        } else {
            address = "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        }
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
