import Foundation

/// Where each developer tool actually keeps its cache.
///
/// People move these with environment variables or tool settings
/// (`NVM_DIR`, `PNPM_HOME`, `HOMEBREW_CACHE`, `GRADLE_USER_HOME`, npm's `cache`
/// setting, ...). An app opened from Finder does not see shell variables, so
/// the tool itself is asked first, then the environment, then the default.
/// Idea from Major Tom (MIT, Copyright (c) 2026 Tom Jordan).
enum ToolLocations {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [String: URL] = [:]

    static func cache(for tool: ToolCleaner, executable: String?) -> URL {
        lock.lock(); if let hit = cached[tool.id] { lock.unlock(); return hit }; lock.unlock()
        let resolved = ask(tool, executable: executable) ?? fromEnvironment(tool.id) ?? DevCleanups.home.appendingPathComponent(tool.cache)
        lock.lock(); cached[tool.id] = resolved; lock.unlock()
        return resolved
    }

    /// Reads the answer from the tool. A blank, failing or slow answer counts as no answer.
    private static func ask(_ tool: ToolCleaner, executable: String?) -> URL? {
        guard let executable else { return nil }
        let arguments: [String]
        var suffix: String?
        switch tool.id {
        case "npm": arguments = ["config", "get", "cache"]; suffix = "_cacache"
        case "pnpm": arguments = ["store", "path"]
        case "yarn": arguments = ["cache", "dir"]
        case "pip": arguments = ["cache", "dir"]
        case "uv": arguments = ["cache", "dir"]
        case "go": arguments = ["env", "GOCACHE"]
        case "brew": arguments = ["--cache"]
        default: return nil
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([URL(fileURLWithPath: executable).deletingLastPathComponent().path] + DevCleanups.searchPaths).joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        let result = CommandRunner.run(executable, arguments, timeout: 6, environment: environment)
        let line = result.output.split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard result.status == 0, line.hasPrefix("/") else { return nil }
        var url = URL(fileURLWithPath: line)
        if let suffix { url.appendPathComponent(suffix) }
        // pnpm reports the versioned store; measure the whole store folder.
        if tool.id == "pnpm", url.lastPathComponent.hasPrefix("v") { url.deleteLastPathComponent() }
        return url
    }

    private static func fromEnvironment(_ id: String) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        func path(_ key: String, _ suffix: String = "") -> URL? {
            guard let value = environment[key], value.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: value).appendingPathComponent(suffix)
        }
        switch id {
        case "npm": return path("npm_config_cache", "_cacache")
        case "pnpm": return path("PNPM_HOME", "store")
        case "yarn": return path("YARN_CACHE_FOLDER")
        case "bun": return path("BUN_INSTALL_CACHE_DIR")
        case "brew": return path("HOMEBREW_CACHE")
        case "go": return path("GOCACHE")
        case "pip": return path("PIP_CACHE_DIR")
        case "uv": return path("UV_CACHE_DIR")
        default: return nil
        }
    }

    /// Gradle and nvm move with an environment variable alone.
    static var gradleHome: URL { ProcessInfo.processInfo.environment["GRADLE_USER_HOME"].map { URL(fileURLWithPath: $0) } ?? DevCleanups.home.appendingPathComponent(".gradle") }
    static var nvmHome: URL { ProcessInfo.processInfo.environment["NVM_DIR"].map { URL(fileURLWithPath: $0) } ?? DevCleanups.home.appendingPathComponent(".nvm") }

    /// Every resolved tool cache, for the package-cache safety rule.
    static var knownCaches: [String] {
        lock.lock(); defer { lock.unlock() }
        return cached.values.map(\.path)
    }

    /// `/usr/bin/git` and friends are placeholders that offer to install the
    /// developer tools when those are missing; they are not the tool.
    static func isPlaceholder(_ executable: String) -> Bool {
        executable.hasPrefix("/usr/bin/") && !developerToolsInstalled
    }
    private static let developerToolsInstalled = CommandRunner.run("/usr/bin/xcode-select", ["-p"], timeout: 3).status == 0
}
