import Foundation

enum CleanupEvidenceKind: String, Codable, Sendable {
    case knownCache
    case dependency
    case buildOutput
    case gitIgnored
    case projectRoot
    case sourceLike
    case sensitive
    case unknown

    var label: String {
        switch self {
        case .knownCache: return "Cache"
        case .dependency: return "Dependencies"
        case .buildOutput: return "Build output"
        case .gitIgnored: return "Git-ignored"
        case .projectRoot: return "Project source"
        case .sourceLike: return "Source-like"
        case .sensitive: return "Protected"
        case .unknown: return "Unknown"
        }
    }
    var isBlocked: Bool { self == .projectRoot || self == .sourceLike || self == .sensitive }
}

struct CleanupEvidence: Codable, Sendable, Equatable {
    let kind: CleanupEvidenceKind
    let detail: String
    let rebuild: String?
    let gitIgnored: Bool
    var label: String { kind.label }
}

/// Cheap, honest evidence labels. The review plan adds a git check-ignore probe;
/// the tree uses the path/name/project-marker heuristics only.
enum CleanupEvidenceService {
    private struct CachePath {
        let prefix: String
        let detail: String
        let rebuild: String
    }

    private static let caches: [CachePath] = {
        let h = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return [
            .init(prefix: h + "/Library/Developer/Xcode/DerivedData", detail: "Xcode build products and indexes.", rebuild: "Xcode rebuilds products and indexes on the next build."),
            .init(prefix: h + "/Library/Caches", detail: "An application or tool cache.", rebuild: "Applications and tools rebuild caches as needed."),
            .init(prefix: h + "/.npm/_cacache", detail: "Downloaded npm package content.", rebuild: "npm downloads packages again."),
            .init(prefix: h + "/Library/pnpm/store", detail: "The pnpm content-addressable store.", rebuild: "pnpm re-links or re-downloads packages."),
            .init(prefix: h + "/.cargo/registry", detail: "Downloaded Cargo crate sources.", rebuild: "Cargo downloads crates again."),
            .init(prefix: h + "/Library/Caches/go-build", detail: "The Go build cache.", rebuild: "go build repopulates the cache."),
            .init(prefix: h + "/Library/Caches/org.swift.swiftpm", detail: "Swift package download cache.", rebuild: "SwiftPM downloads packages again."),
            .init(prefix: h + "/Library/Caches/Homebrew", detail: "Downloaded Homebrew bottles and sources.", rebuild: "Homebrew downloads again if needed."),
            .init(prefix: h + "/.gradle/caches", detail: "Gradle dependency and build caches.", rebuild: "Gradle re-downloads dependencies."),
            .init(prefix: h + "/Library/Caches/pip", detail: "Downloaded Python wheels and HTTP cache.", rebuild: "pip downloads packages again."),
            .init(prefix: h + "/Library/Caches/CocoaPods", detail: "CocoaPods spec and pod cache.", rebuild: "pod install downloads again.")
        ]
    }()

    static let dependencyNames: Set<String> = ["node_modules", "pods", ".venv", "venv", "vendor", "bower_components", "carthage", "target"]
    static let outputNames: Set<String> = ["build", "dist", ".next", ".nuxt", ".svelte-kit", ".turbo", "out", "coverage", "test-results", ".build", "deriveddata", "htmlcov"]
    static let rebuildableNames = dependencyNames.union(outputNames).union(["release", "debug", "bin", "obj"])
    private static let sourceExtensions: Set<String> = ["swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "java", "kt", "kts", "rs", "go", "py", "rb", "php", "cs", "ts", "tsx", "js", "jsx", "vue", "svelte", "sh", "bash", "zsh", "sql", "dart", "ex", "exs", "lua", "r", "scala", "clj", "gradle"]
    private static let buildExtensions: Set<String> = ["o", "obj", "a", "so", "dylib", "class", "pyc", "pyd", "wasm", "map", "d", "tbd", "pdb"]

    static func isSourceFile(_ url: URL) -> Bool { sourceExtensions.contains(url.pathExtension.lowercased()) }
    static func isBuildArtifact(_ url: URL) -> Bool { buildExtensions.contains(url.pathExtension.lowercased()) || ["app", "framework", "dsym", "xcarchive"].contains(url.pathExtension.lowercased()) }

    static func classify(_ url: URL, gitIgnored: Bool? = nil, sourceCheck: Bool = false) -> CleanupEvidence {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent.lowercased()
        if CleanupSafety.isSensitive(path) {
            return CleanupEvidence(kind: .sensitive, detail: "Source-control metadata, credentials, or a personal data store.", rebuild: nil, gitIgnored: false)
        }
        let isDirectory = url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isDirectory, FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            return CleanupEvidence(kind: .projectRoot, detail: "Contains a Git repository. Nuke Sweep refuses to move a project or source root whole.", rebuild: nil, gitIgnored: gitIgnored ?? false)
        }
        if let cache = caches.first(where: { path == $0.prefix || path.hasPrefix($0.prefix + "/") }) {
            return CleanupEvidence(kind: .knownCache, detail: cache.detail, rebuild: cache.rebuild, gitIgnored: gitIgnored ?? false)
        }
        if dependencyNames.contains(name) {
            return CleanupEvidence(kind: .dependency, detail: "A dependency or package store that can be recreated.", rebuild: rebuildAdvice(for: name), gitIgnored: gitIgnored ?? false)
        }
        if outputNames.contains(name) {
            return CleanupEvidence(kind: .buildOutput, detail: "Generated build output. A copied manifest inside does not make it source.", rebuild: rebuildAdvice(for: name), gitIgnored: gitIgnored ?? false)
        }
        if isDirectory, sourceCheck, looksLikeSourceDirectory(url) {
            return CleanupEvidence(kind: .sourceLike, detail: "Contains source-like files and no clear build-output signature. Nuke Sweep refuses to move it whole.", rebuild: nil, gitIgnored: gitIgnored ?? false)
        }
        if gitIgnored == true {
            return CleanupEvidence(kind: .gitIgnored, detail: "Git reports this path as ignored, which is evidence it is generated.", rebuild: "Rebuild or regenerate it from the tracked source.", gitIgnored: true)
        }
        if isDirectory, ReviewPlanner.looksLikeProjectRoot(url) {
            return CleanupEvidence(kind: .projectRoot, detail: "Contains project or source markers at its top level. Nuke Sweep refuses to move it whole.", rebuild: nil, gitIgnored: false)
        }
        return CleanupEvidence(kind: .unknown, detail: "Nuke Sweep has no reliable evidence about this item. Review it before selecting.", rebuild: nil, gitIgnored: gitIgnored ?? false)
    }

    /// A bounded, conservative source-tree probe. It skips dependency/build names
    /// and treats any compiled artifact as enough build evidence to stop guessing.
    static func looksLikeSourceDirectory(_ root: URL) -> Bool {
        if rebuildableNames.contains(root.lastPathComponent.lowercased()) { return false }
        let deadline = Date().addingTimeInterval(1)
        var visited = 0, source = 0, build = 0
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 2, visited < 800, Date() <= deadline, build == 0 else { return }
            _ = try? DirectoryEntries.visit(dir, shouldContinue: { visited < 800 && Date() <= deadline && build == 0 }) { child in
                visited += 1
                let name = child.lastPathComponent.lowercased()
                guard !rebuildableNames.contains(name), ![".git", ".hg", ".svn"].contains(name) else { return }
                if name.hasSuffix(".app") || name.hasSuffix(".framework") || name.hasSuffix(".dsym") || name.hasSuffix(".xcarchive") { build += 1; return }
                var s = stat()
                guard lstat(child.path, &s) == 0 else { return }
                if s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) {
                    if depth < 2 { walk(child, depth: depth + 1) }
                } else {
                    let ext = child.pathExtension.lowercased()
                    if sourceExtensions.contains(ext) { source += 1 }
                    else if buildExtensions.contains(ext) { build += 1 }
                }
            }
        }
        walk(root, depth: 0)
        return source > 0 && build == 0
    }

    static func repoRoot(for url: URL) -> URL? {
        let fm = FileManager.default
        var cursor = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        for _ in 0..<24 {
            if fm.fileExists(atPath: cursor.appendingPathComponent(".git").path) { return cursor }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return nil
    }

    static func gitTracked(_ url: URL) -> Bool? {
        guard let repo = repoRoot(for: url), FileManager.default.fileExists(atPath: "/usr/bin/git") else { return nil }
        let repoPath = repo.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        let rel: String
        if itemPath == repoPath { rel = "." }
        else if itemPath.hasPrefix(repoPath + "/") { rel = String(itemPath.dropFirst(repoPath.count + 1)) }
        else { return nil }
        let r = CommandRunner.run("/usr/bin/git", ["-C", repo.path, "ls-files", "-z", "--", rel], timeout: 2)
        guard r.status == 0 else { return nil }
        return !r.output.isEmpty
    }

    static func rebuildAdvice(for name: String) -> String {
        switch name {
        case "node_modules": return "Reinstall with npm, pnpm, yarn, or bun."
        case "pods": return "Run pod install."
        case ".venv", "venv": return "Recreate the virtual environment and reinstall dependencies."
        case "target": return "Run cargo build."
        case "vendor": return "Reinstall dependencies with your package manager."
        case "carthage": return "Run carthage bootstrap."
        case "build", "dist", "out", "coverage", "test-results": return "Rebuild from source."
        case ".next", ".nuxt", ".svelte-kit": return "Rebuild the site or app."
        case ".build", "deriveddata": return "Rebuild with Xcode or SwiftPM."
        default: return "Regenerate it from source."
        }
    }

    /// A bounded git probe used by the review plan, where only selected items are checked.
    static func gitIgnored(_ url: URL) -> Bool? {
        guard let repo = repoRoot(for: url), FileManager.default.fileExists(atPath: "/usr/bin/git") else { return nil }
        let r = CommandRunner.run("/usr/bin/git", ["-C", repo.path, "check-ignore", "-q", "--", url.path], timeout: 2)
        if r.status == 0 { return true }
        if r.status == 1 { return false }
        return nil
    }
}

struct CleanupPlan: Codable {
    let generatedAt: Date
    let note: String
    let totalLogicalSize: Int64
    let items: [Item]
    let warnings: [String]
    struct Item: Codable {
        let path: String
        let size: Int64
        let directory: Bool
        let evidence: CleanupEvidence?
    }
}
