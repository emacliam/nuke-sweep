import Foundation

/// Development builds never reuse production preferences, history, keys or URLs.
enum AppEnvironment {
    static let productionBundleID = "com.zyncraft.nukesweep"
    private static let legacyBundleID = "local.nuke.mac"
    private static let migrationKey = "nuke.bundleIdentityMigrationComplete"
    static let developmentBundleID = "local.nuke.mac.development"
    static var isDevelopment: Bool { Bundle.main.bundleIdentifier == developmentBundleID }
    static var supportName: String { isDevelopment ? "Nuke Sweep Development" : "Nuke" }
    static var supportRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").appendingPathComponent(supportName) }
    /// Production receipts and scan history already live outside the bundle domain.
    /// Only preferences need copying; retain the old domain for rollback.
    static func migrateProductionPreferences() {
        guard Bundle.main.bundleIdentifier == productionBundleID else { return }
        migratePreferences(in: .standard, from: legacyBundleID, to: productionBundleID)
    }

    static func migratePreferences(in defaults: UserDefaults, from legacyDomain: String, to currentDomain: String) {
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[migrationKey] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        for (key, value) in legacy where key.hasPrefix("nuke.") && current[key] == nil {
            current[key] = value
        }
        current[migrationKey] = true
        defaults.setPersistentDomain(current, forName: currentDomain)
    }

    static var urlScheme: String { isDevelopment ? "nuke-development" : "nuke" }
}
