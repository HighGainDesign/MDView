import Foundation
import XCTest
@testable import MDView

final class ReaderPreferencesTests: XCTestCase {
    override class func tearDown() {
        ReaderPreferences.defaults.removePersistentDomain(forName: "MDViewTests.ReaderPreferences.\(ProcessInfo.processInfo.processIdentifier)")
        super.tearDown()
    }

    func testMigrationPreservesLegacyChoiceButNeverOverwritesSharedChoice() throws {
        let legacySuite = "MDViewTests.LegacyAppearance.\(UUID().uuidString)"
        let sharedSuite = "MDViewTests.SharedAppearance.\(UUID().uuidString)"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedSuite))
        defer {
            legacy.removePersistentDomain(forName: legacySuite)
            shared.removePersistentDomain(forName: sharedSuite)
        }
        legacy.set("light", forKey: ReaderPreferences.appearanceKey)
        ReaderPreferences.migrateAppearance(from: legacy, to: shared)
        XCTAssertEqual(ReaderPreferences.appearance(in: shared), .light)
        shared.set("dark", forKey: ReaderPreferences.appearanceKey)
        ReaderPreferences.migrateAppearance(from: legacy, to: shared)
        XCTAssertEqual(ReaderPreferences.appearance(in: shared), .dark)
        XCTAssertEqual(legacy.string(forKey: ReaderPreferences.appearanceKey), "light")
    }

    func testIndependentPreferenceReadersSeeChangesAndSafelyDefaultToSystem() throws {
        let suite = "MDViewTests.PreferenceReaders.\(UUID().uuidString)"
        let app = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preview = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { app.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ReaderPreferences.appearance(in: preview), .system)
        for appearance in DocumentAppearance.allCases {
            app.set(appearance.rawValue, forKey: ReaderPreferences.appearanceKey)
            XCTAssertEqual(ReaderPreferences.appearance(in: preview), appearance)
        }
        app.set("unknown", forKey: ReaderPreferences.appearanceKey)
        XCTAssertEqual(ReaderPreferences.appearance(in: preview), .system)
    }
}
