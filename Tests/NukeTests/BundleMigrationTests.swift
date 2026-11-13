import Foundation
import XCTest
@testable import Nuke

final class BundleMigrationTests: XCTestCase {
    func testCopiesOnlyMissingAppPreferencesOnce() throws {
        let legacy = "nuke.tests.legacy." + UUID().uuidString
        let current = "nuke.tests.current." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: current))
        defer {
            defaults.removePersistentDomain(forName: legacy)
            defaults.removePersistentDomain(forName: current)
        }

        let scan = Data([1, 2, 3])
        defaults.setPersistentDomain(["nuke.workspace": scan, "nuke.appearance": "light", "other": true], forName: legacy)
        defaults.setPersistentDomain(["nuke.appearance": "dark"], forName: current)

        AppEnvironment.migratePreferences(in: defaults, from: legacy, to: current)

        var migrated = try XCTUnwrap(defaults.persistentDomain(forName: current))
        XCTAssertEqual(migrated["nuke.workspace"] as? Data, scan)
        XCTAssertEqual(migrated["nuke.appearance"] as? String, "dark")
        XCTAssertNil(migrated["other"])
        XCTAssertEqual(defaults.persistentDomain(forName: legacy)?["nuke.workspace"] as? Data, scan)

        migrated.removeValue(forKey: "nuke.workspace")
        defaults.setPersistentDomain(migrated, forName: current)
        AppEnvironment.migratePreferences(in: defaults, from: legacy, to: current)
        XCTAssertNil(defaults.persistentDomain(forName: current)?["nuke.workspace"])
    }
}
