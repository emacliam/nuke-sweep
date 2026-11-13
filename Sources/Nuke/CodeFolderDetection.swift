import Foundation

/// Finds where the user actually keeps their code.
///
/// The Projects screen previously opened on a folder picker and a paragraph,
/// which asks the person to do work the app can do itself. Developers keep source
/// in a small set of conventional places, and a directory that contains several
/// project markers is unambiguous evidence.
///
/// Read-only and bounded: it looks one level inside a handful of candidate
/// directories and counts markers. It never descends into projects, never follows
/// symlinks out of the home directory, and suggests rather than selects.
enum CodeFolderDetection {
    /// Conventional locations, in rough order of how strongly each signals intent.
    /// `~/Developer` gets a dedicated Finder icon from Apple, so it is the
    /// strongest convention on this platform.
    private static let candidates = [
        "Developer", "Projects", "projects", "code", "Code", "src", "Source",
        "repos", "Repos", "git", "workspace", "Workspace", "dev", "Sites"
    ]

    /// Markers that identify a directory as a project root without opening it.
    private static let markers: Set<String> = [
        "package.json", "Cargo.toml", "Package.swift", "go.mod", "pyproject.toml",
        "requirements.txt", "Gemfile", "pom.xml", "build.gradle", "build.gradle.kts",
        "pubspec.yaml", "composer.json", "deno.json", "mix.exs", ".git"
    ]

    struct Candidate: Identifiable, Sendable {
        var id: String { url.path }
        let url: URL
        /// How many immediate children look like project roots.
        let projectCount: Int
        var name: String { url.lastPathComponent }
        /// Home-relative, so a nested folder reads as where it actually is.
        var displayPath: String {
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
    }

    /// Bounded scan of the conventional directories. `limit` caps how many
    /// children are examined in any one of them so a folder with thousands of
    /// entries cannot turn a suggestion into a scan.
    ///
    /// `deep` also looks one level inside ~/Documents, where plenty of people keep
    /// a `code` or `work` folder that the conventional names miss. It is only
    /// used when the person has asked for a check: reading ~/Documents can raise
    /// a macOS permission prompt, which should never appear just from opening a
    /// screen.
    static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser, limit: Int = 200, deep: Bool = false) -> [Candidate] {
        let manager = FileManager.default
        var found: [Candidate] = []
        if deep {
            let documents = home.appendingPathComponent("Documents")
            let children = (try? manager.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            for child in children.prefix(60) {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      child.resolvingSymlinksInPath().path.hasPrefix(home.path) else { continue }
                // Two or more projects, so a single stray repository in Documents
                // is not mistaken for where someone keeps their code.
                let count = projectCount(in: child, limit: limit, manager: manager)
                if count >= 2 { found.append(Candidate(url: child, projectCount: count)) }
            }
        }
        for name in candidates {
            let root = home.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            // A symlinked candidate could point anywhere; only suggest real
            // directories inside the home folder.
            guard root.resolvingSymlinksInPath().path.hasPrefix(home.path) else { continue }
            let count = projectCount(in: root, limit: limit, manager: manager)
            guard count > 0 else { continue }
            found.append(Candidate(url: root, projectCount: count))
        }
        return found.sorted { $0.projectCount == $1.projectCount ? $0.name < $1.name : $0.projectCount > $1.projectCount }
    }

    private static func projectCount(in root: URL, limit: Int, manager: FileManager) -> Int {
        guard let children = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var count = 0
        for child in children.prefix(limit) {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if looksLikeProject(child, manager: manager) { count += 1 }
        }
        return count
    }

    /// One `contentsOfDirectory` per candidate child, matched against the marker
    /// set. Cheaper than stat-ing every marker individually.
    private static func looksLikeProject(_ url: URL, manager: FileManager) -> Bool {
        guard let names = try? manager.contentsOfDirectory(atPath: url.path) else { return false }
        return names.contains { markers.contains($0) }
    }
}
