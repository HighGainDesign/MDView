import AppKit
import SwiftUI
import XCTest
@testable import MDView

@MainActor
final class LayoutPolishTests: XCTestCase {
    func testSetupFitsACompactWindowWithoutHorizontalOverflow() async throws {
        let name = "MDViewTests.SetupLayout.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let session = SetupSession(defaults: defaults, draftsAvailable: true, openExtensions: {}, importDrafts: {})
        let controller = SetupWindowController(session: session)
        controller.showWindow(nil); defer { controller.close() }
        let window = try XCTUnwrap(controller.window), view = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 520, height: 480))
        for _ in 0..<20 { view.layoutSubtreeIfNeeded(); await Task.yield() }
        XCTAssertLessThanOrEqual(view.fittingSize.width, 521, "Setup must fit a compact window rather than clipping its fixed-width content")
    }

    func testTranslatedSetupAndSettingsUseTheirAllocatedWindowBounds() async throws {
        let original = SettingsNavigation.shared.page
        defer { SettingsNavigation.shared.page = original }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MDView-1.5-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in ["en", "es", "zh-Hans", "zh-Hant", "ja", "fr", "de"] {
            let session = SetupSession(draftsAvailable: true, openExtensions: {}, importDrafts: {})
            let setup = NSHostingController(rootView: SetupView(session: session, done: {}).environment(\.locale, Locale(identifier: language)))
            let window = NSWindow(contentViewController: setup)
            window.isReleasedWhenClosed = false; window.setContentSize(NSSize(width: 520, height: 480)); window.orderFront(nil)
            for _ in 0..<10 { setup.view.layoutSubtreeIfNeeded(); await Task.yield() }
            XCTAssertLessThanOrEqual(setup.view.fittingSize.width, 521, language)
            try capture(setup.view, at: directory.appendingPathComponent("setup-" + language + ".png"))
            window.close()
            let settings = NSHostingController(rootView: SettingsView().environment(\.locale, Locale(identifier: language)))
            let settingsWindow = NSWindow(contentViewController: settings)
            settingsWindow.isReleasedWhenClosed = false; settingsWindow.setContentSize(NSSize(width: 620, height: 680)); settingsWindow.orderFront(nil)
            for page in [SettingsNavigation.Page.reading, .speech, .content, .integrations] {
                SettingsNavigation.shared.page = page
                for _ in 0..<10 { settings.view.layoutSubtreeIfNeeded(); await Task.yield() }
                XCTAssertEqual(settings.view.bounds.width, 620, accuracy: 1)
                XCTAssertEqual(settings.view.bounds.height, 680, accuracy: 1)
                try capture(settings.view, at: directory.appendingPathComponent("settings-\(page)-\(language).png"))
            }
            settingsWindow.close()
        }
    }

    private func capture(_ view: NSView, at url: URL) throws {
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
    }

}
