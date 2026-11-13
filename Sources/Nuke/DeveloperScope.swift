import Foundation

/// A remembered developer folder with an explicit cleanup policy and path exclusions.
/// Exclusions are relative paths; a folder that contains an excluded path cannot be
/// selected, so a reviewed folder move can never take an excluded subtree with it.
struct DeveloperScope: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var label: String
    var path: String
    var cleanupAllowed = false
    var exclusions: [String] = []

    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { label.isEmpty ? url.lastPathComponent : label }
    var hasExclusions: Bool { !exclusions.isEmpty }

    func relativePath(_ candidate: URL) -> String? {
        let root = path
        let candidatePath = candidate.path
        guard candidatePath == root || candidatePath.hasPrefix(root + "/") else { return nil }
        return String(candidatePath.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Used by the scanner for every entry; avoids per-entry URL standardization.
    func isExcluded(_ candidate: URL) -> Bool {
        let root = path
        let candidatePath = candidate.path
        guard candidatePath.hasPrefix(root + "/") else { return false }
        let rel = String(candidatePath.dropFirst(root.count + 1))
        return exclusions.contains { rel == $0 || rel.hasPrefix($0 + "/") }
    }

    /// A folder that is, or contains, an excluded path is not selectable.
    func blocksSelection(_ item: DiskItem) -> Bool {
        guard let rel = relativePath(item.url), !rel.isEmpty else { return true }
        for rule in exclusions {
            if rel == rule || rel.hasPrefix(rule + "/") { return true }
            if rule.hasPrefix(rel + "/") { return true }
        }
        return false
    }

    /// Shared policy for proposals and cleanup. Callers performing a move also
    /// supply the resolved parent path so an alias cannot bypass an exclusion.
    static func cleanupBlock(for path: String, in scopes: [Self], resolvingRoots: Bool = false) -> String? {
        func policyPath(_ value: String) -> String {
            value.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        let candidate = policyPath(path)
        for scope in scopes {
            let root = policyPath(scope.url.standardizedFileURL.path)
            let resolved = resolvingRoots ? policyPath(scope.url.resolvingSymlinksInPath().standardizedFileURL.path) : root
            for base in Set([root, resolved]) {
                if candidate == base || base.hasPrefix(candidate + "/") {
                    return "This selection includes the developer scope \(scope.displayName). Select items inside the scope."
                }
                let prefix = base == "/" ? base : base + "/"
                guard candidate.hasPrefix(prefix) else { continue }
                if !scope.cleanupAllowed {
                    return "\(scope.displayName) is configured for inspection only."
                }
                for exclusion in scope.exclusions {
                    let excluded = prefix + policyPath(exclusion)
                    if candidate == excluded || candidate.hasPrefix(excluded + "/") || excluded.hasPrefix(candidate + "/") {
                        return "This selection includes an excluded path in \(scope.displayName)."
                    }
                }
            }
        }
        return nil
    }

    /// Applies AI-proposed exclusions to an existing scope or a new scope for `root`.
    /// Only paths inside the root are stored; duplicates are removed.
    static func applyingPlanExclusions(root: URL, existing: DeveloperScope?, additions: [URL]) -> DeveloperScope {
        let standardized = root.standardizedFileURL
        var scope = existing ?? DeveloperScope(label: standardized.lastPathComponent, path: standardized.path, cleanupAllowed: true, exclusions: [])
        for url in additions {
            guard let relative = scope.relativePath(url.standardizedFileURL), !relative.isEmpty else { continue }
            if !scope.exclusions.contains(relative) { scope.exclusions.append(relative) }
        }
        return scope
    }

    static func normalizeExclusions(_ text: String, root: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" }) {
            var rule = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
            guard !rule.isEmpty else { continue }
            if rule.hasPrefix(rootPath + "/") { rule = String(rule.dropFirst(rootPath.count + 1)) }
            while rule.hasPrefix("./") { rule.removeFirst(2) }
            while rule.hasPrefix("/") { rule.removeFirst() }
            while rule.hasSuffix("/") { rule.removeLast() }
            guard !rule.isEmpty, !rule.split(separator: "/").contains("..") else { continue }
            if seen.insert(rule).inserted { result.append(rule) }
        }
        return result
    }
}

struct ScopeMeasurement {
    let items: [DiskItem]
    let measured: Date
    let limited: Bool
    let skipped: Int
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
    var incomplete: Bool { limited || skipped > 0 || items.contains { $0.incomplete } }
    var unavailable: Bool { items.isEmpty && skipped > 0 }
}


/// Starting points for a new scope. Exclusions are paths to keep, not paths to clean.
struct DeveloperScopePreset: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let exclusions: [String]

    var scope: DeveloperScope {
        DeveloperScope(label: "", path: "", cleanupAllowed: true, exclusions: exclusions)
    }

    static let all: [DeveloperScopePreset] = [
        .init(id: "node", title: "Node / web project",
              detail: "Keeps source, assets, and project config; leaves node_modules, build, dist, .next, and coverage selectable.",
              exclusions: [".git", "src", "public", "assets", "README.md", "package.json", "tsconfig.json"]),
        .init(id: "python", title: "Python project",
              detail: "Keeps source, tests, docs, and project config; leaves .venv, caches, build, and dist selectable.",
              exclusions: [".git", "src", "tests", "docs", "README.md", "pyproject.toml", "requirements.txt"]),
        .init(id: "rust", title: "Rust project",
              detail: "Keeps source and manifests; leaves target selectable.",
              exclusions: [".git", "src", "tests", "Cargo.toml", "Cargo.lock", "README.md"]),
        .init(id: "swift", title: "Swift package / Xcode project",
              detail: "Keeps source, tests, and package manifest; leaves .build, build, and DerivedData selectable.",
              exclusions: [".git", "Sources", "Tests", "Package.swift", "README.md"]),
        .init(id: "monorepo", title: "Monorepo",
              detail: "Keeps git metadata and top-level docs; expand packages to select their build and dependency folders.",
              exclusions: [".git", "docs", "README.md"]),
        .init(id: "deno", title: "Deno / TypeScript project",
              detail: "Keeps source, tests, docs, and Deno manifests; leaves build-like folders selectable.",
              exclusions: [".git", "src", "tests", "docs", "README.md", "deno.json", "deno.jsonc", "deno.lock"]),
        .init(id: "flutter", title: "Flutter / Dart project",
              detail: "Keeps lib, tests, and pubspec; leaves .dart_tool and build selectable.",
              exclusions: [".git", "lib", "test", "README.md", "pubspec.yaml", "pubspec.lock"]),
        .init(id: "jvm", title: "Java / Kotlin project",
              detail: "Keeps source and build manifests; leaves build, target, and Gradle/Maven output selectable.",
              exclusions: [".git", "src", "README.md", "build.gradle", "build.gradle.kts", "settings.gradle", "pom.xml"]),
        .init(id: "dotnet", title: ".NET project",
              detail: "Keeps source and project metadata; leaves bin and obj selectable.",
              exclusions: [".git", "src", "tests", "README.md", "global.json", "Directory.Build.props"])
    ]
}
