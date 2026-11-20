import Foundation

/// Stale projects, and how to bring their dependencies back.
/// Approach adapted from Major Tom (MIT, Copyright (c) 2026 Tom Jordan).
enum ProjectHibernation {
    static let staleDays = 90

    /// Install commands that restore a project's dependencies, read from its
    /// lockfiles: JavaScript first, then CocoaPods, then other ecosystems.
    static func restoreCommands(_ root: URL) -> [String] {
        let fm = FileManager.default
        func has(_ name: String, in folder: URL = root) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        var commands: [String] = []
        if has("pnpm-lock.yaml") { commands.append("pnpm install") }
        else if has("yarn.lock") { commands.append("yarn install") }
        else if has("bun.lock") || has("bun.lockb") { commands.append("bun install") }
        else if has("package-lock.json") || has("npm-shrinkwrap.json") { commands.append("npm ci") }
        else if has("package.json") { commands.append("npm install") }
        if has("Podfile") { commands.append("pod install") }
        else if has("Podfile", in: root.appendingPathComponent("ios")) { commands.append("cd ios && pod install") }
        if has("Gemfile.lock") { commands.append("bundle install") }
        if has("pubspec.lock") || has("pubspec.yaml") { commands.append("flutter pub get") }
        if has("poetry.lock") { commands.append("poetry install") }
        else if has("Pipfile.lock") { commands.append("pipenv install") }
        else if has("uv.lock") { commands.append("uv sync") }
        if has("Cargo.lock") { commands.append("cargo build") }
        if has("Package.resolved") || has("Package.swift") { commands.append("swift build") }
        if has("gradlew") { commands.append("./gradlew build") }
        return commands
    }

    /// Newest of the last commit and the newest change to anything at the top
    /// of the project that is not generated. Git is only read.
    static func lastActivity(_ root: URL, generated: Set<String>) -> Date? {
        var newest: Date?
        let git = CommandRunner.run("/usr/bin/git", ["--no-optional-locks", "-C", root.path, "log", "-1", "--format=%ct"], timeout: 5)
        if git.status == 0, let seconds = Double(git.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            newest = Date(timeIntervalSince1970: seconds)
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for child in children where !generated.contains(child.lastPathComponent) && child.lastPathComponent != ".git" {
            if let date = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                newest = max(newest ?? date, date)
            }
        }
        return newest
    }

    // Pinned projects are never called stale; hidden ones are not listed.
    private static let pinnedKey = "nuke.projects.pinned", hiddenKey = "nuke.projects.hidden"
    static var pinned: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: pinnedKey) }
    }
    static var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenKey) }
    }
}
