import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var welcome: NSWindowController?
    private var settings: NSWindowController?
    private var setup: SetupWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        ReaderPreferences.migrateAppearance(from: .standard, to: ReaderPreferences.defaults)
        buildMenus()
        _ = NSDocumentController.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await Task.yield()
            showStartupTips()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // AppKit calls this when launching without a document to open.
        showWelcome()
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let documents = NSDocumentController.shared.documents
            if documents.isEmpty { showWelcome() }
            else { documents.forEach { $0.showWindows() } }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                    if let error { NSApp.presentError(error) }
                    else { self?.welcome?.close() }
                }
            } else {
                if url.scheme?.lowercased() == "mdview", url.host == "stream" {
                    showLiveStreamingPreview()
                    continue
                }
                do {
                    let request = try PreviewRequest(url: url)
                    let document = MarkdownDocument(preview: request)
                    NSDocumentController.shared.addDocument(document)
                    document.makeWindowControllers()
                    document.showWindows()
                    welcome?.close()
                } catch { NSApp.presentError(error) }
            }
        }
        application.activate(ignoringOtherApps: true)
    }

    func showWelcome() {
        guard NSDocumentController.shared.documents.isEmpty else {
            documentDidOpen()
            return
        }
        if welcome == nil {
            let view = WelcomeView(open: { NSDocumentController.shared.openDocument(nil) },
                                   liveStreaming: { [weak self] in self?.showLiveStreamingPreview() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "MDView"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 370))
            window.center()
            welcome = NSWindowController(window: window)
        }
        welcome?.showWindow(nil)
    }

    func documentDidOpen() {
        welcome?.close()
    }

    func showLiveStreamingPreview() {
        if let document = NSDocumentController.shared.documents.compactMap({ $0 as? MarkdownDocument })
            .first(where: { $0.reader.isStreamingPreview }) {
            document.reader.streamPaused = false
            document.showWindows()
        } else {
            let document = MarkdownDocument(streamingPreview: true)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        }
        welcome?.close()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func liveStreamingPreview(_ sender: Any?) { showLiveStreamingPreview() }

    @objc private func showSettings(_ sender: Any?) {
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "MDView Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 600, height: 680))
            window.center()
            settings = NSWindowController(window: window)
        }
        settings?.showWindow(nil)
    }

    func showStartupTips(force: Bool = false) {
        if let setup, setup.window?.isVisible == true {
            setup.showWindow(nil)
            return
        }
        guard force || StartupTips.shouldShow() else { return }
        let controller = SetupWindowController()
        setup = controller
        controller.showWindow(nil)
    }

    private var reader: ReaderState? {
        (NSDocumentController.shared.currentDocument as? MarkdownDocument)?.reader
    }

    @objc private func find(_ sender: Any?) { reader?.showFind = true }
    @objc private func reload(_ sender: Any?) { reader?.reload() }
    @objc private func zoomIn(_ sender: Any?) { reader?.changeZoom(by: 0.1) }
    @objc private func zoomOut(_ sender: Any?) { reader?.changeZoom(by: -0.1) }
    @objc private func actualSize(_ sender: Any?) { reader?.zoom = 1 }
    @objc private func toggleOutline(_ sender: Any?) { reader?.showOutline.toggle() }
    @objc private func reviewChanges(_ sender: Any?) {
        guard let reader, reader.fileURL != nil else { return }
        reader.showChanges.toggle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        add("Clear Menu", to: menu, action: #selector(NSDocumentController.clearRecentDocuments(_:)))
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        application(NSApp, open: [url])
    }

    private func buildMenus() {
        let bar = NSMenu()
        let app = NSMenu(title: "MDView")
        add("About MDView", to: app, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add("Settings…", to: app, action: #selector(showSettings(_:)), key: ",", target: self)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let serviceItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        serviceItem.submenu = services
        app.addItem(serviceItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add("Hide MDView", to: app, action: #selector(NSApplication.hide(_:)), key: "h")
        add("Hide Others", to: app, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        add("Show All", to: app, action: #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add("Quit MDView", to: app, action: #selector(NSApplication.terminate(_:)), key: "q")
        attach(app, to: bar)

        let file = NSMenu(title: "File")
        add("Open…", to: file, action: #selector(NSDocumentController.openDocument(_:)), key: "o")
        add("Live Streaming Preview", to: file, action: #selector(liveStreamingPreview(_:)), target: self)
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = self
        add("Clear Menu", to: recent, action: #selector(NSDocumentController.clearRecentDocuments(_:)))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        file.addItem(recentItem)
        file.addItem(.separator())
        add("Close Window", to: file, action: #selector(NSWindow.performClose(_:)), key: "w")
        attach(file, to: bar)

        let edit = NSMenu(title: "Edit")
        add("Copy", to: edit, action: #selector(NSText.copy(_:)), key: "c")
        add("Select All", to: edit, action: #selector(NSText.selectAll(_:)), key: "a")
        edit.addItem(.separator())
        add("Find…", to: edit, action: #selector(find(_:)), key: "f", target: self)
        attach(edit, to: bar)

        let view = NSMenu(title: "View")
        add("Reload", to: view, action: #selector(reload(_:)), key: "r", target: self)
        add("Review Changes", to: view, action: #selector(reviewChanges(_:)), key: "r", modifiers: [.command, .shift], target: self)
        add("Toggle Outline", to: view, action: #selector(toggleOutline(_:)), key: "o", modifiers: [.command, .option], target: self)
        view.addItem(.separator())
        add("Zoom In", to: view, action: #selector(zoomIn(_:)), key: "+", target: self)
        add("Zoom Out", to: view, action: #selector(zoomOut(_:)), key: "-", target: self)
        add("Actual Size", to: view, action: #selector(actualSize(_:)), key: "0", target: self)
        attach(view, to: bar)

        let window = NSMenu(title: "Window")
        add("Minimize", to: window, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        add("Zoom", to: window, action: #selector(NSWindow.performZoom(_:)))
        attach(window, to: bar)
        NSApp.windowsMenu = window
        NSApp.mainMenu = bar
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "",
                     modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
    }

    private func attach(_ menu: NSMenu, to bar: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        bar.addItem(item)
    }
}
