import Foundation
import Darwin

enum GitTrackingInspection: Equatable, Sendable {
    case outsideRepository, untracked, tracked, unavailable(String)
    var tracked: Bool? {
        switch self { case .tracked: return true; case .untracked: return false; default: return nil }
    }
    func requireUntracked() throws {
        switch self {
        case .tracked: throw ReviewPlanner.SafetyError.tracked
        case .unavailable(let reason): throw GitInspectionFailure(reason: reason)
        case .outsideRepository, .untracked: break
        }
    }
}
struct GitInspectionFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { "Could not verify Git tracking. " + reason + " Nothing will be moved for this item; resolve the issue and review again." }
}
enum GitInspection {
    enum Repository {
        case found(URL), absent, unavailable(String)
    }
    static func repository(for url: URL) -> Repository {
        repository(at: inspectionPath(url))
    }

    /// Resolve aliases in the parent path without following a selected link.
    private static func inspectionPath(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        if path == "/" { return URL(fileURLWithPath: "/", isDirectory: true) }
        let parent = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent, isDirectory: true)
        return parent.resolvingSymlinksInPath()
            .appendingPathComponent((path as NSString).lastPathComponent)
            .standardizedFileURL
    }

    /// Inspect the candidate and every ancestor. Access failures leave tracking
    /// unknown rather than reporting that the path is outside a repository.
    private static func repository(at url: URL) -> Repository {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return .unavailable("The selected item could not be read: " + String(cString: strerror(errno)) + ".")
        }
        let path = url.path
        var cursor = info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            ? path : (path as NSString).deletingLastPathComponent
        while !cursor.isEmpty {
            let metadataPath = (cursor as NSString).appendingPathComponent(".git")
            var metadata = stat()
            if lstat(metadataPath, &metadata) == 0 {
                return .found(URL(fileURLWithPath: cursor, isDirectory: true))
            }
            let code = errno
            if code != ENOENT && code != ENOTDIR {
                return .unavailable("Repository metadata could not be inspected in " + cursor + ": " + String(cString: strerror(code)) + ".")
            }
            if cursor == "/" { break }
            cursor = (cursor as NSString).deletingLastPathComponent
        }
        return .absent
    }

    static func inspect(_ url: URL, run: (String, [String], TimeInterval) -> CommandResult = runGit) -> GitTrackingInspection {
        let candidate = inspectionPath(url)
        let root: URL
        switch repository(at: candidate) {
        case .absent: return .outsideRepository
        case .unavailable(let reason): return .unavailable(reason + " Check folder access before retrying.")
        case .found(let value): root = value
        }
        let prefix = root.path == "/" ? "/" : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(prefix) else {
            return .unavailable("The selected path no longer belongs to its repository.")
        }
        var arguments = ["--literal-pathspecs", "--no-optional-locks", "-c", "core.fsmonitor=false"]
        if let indexDirectory = ownedIndexDirectory(in: root) {
            // Index-only inspection does not need Git to enter the worktree.
            // On macOS that chdir/getcwd can stall inside protected folders.
            arguments += ["-c", "core.bare=true", "-C", "/", "--git-dir=" + indexDirectory.path]
        } else {
            arguments += ["-C", root.path]
        }
        arguments += ["ls-files", "--cached", "-z"]
        if candidate.path != root.path {
            arguments += ["--", String(candidate.path.dropFirst(prefix.count))]
        }
        let result = run("/usr/bin/git", arguments, 2)
        guard result.status == 0 else { return .unavailable(failureReason(result)) }
        if result.output.isEmpty { return .untracked }
        if result.output.contains("\0") { return .tracked }
        return .unavailable("Git returned an unexpected index listing.")
    }

    /// Retain Git's normal discovery and ownership checks for linked worktrees,
    /// shared repositories, and layouts that use indirect metadata.
    private static func ownedIndexDirectory(in root: URL) -> URL? {
        let metadata = root.appendingPathComponent(".git", isDirectory: true)
        for path in [root.path, metadata.path] {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  info.st_uid == geteuid() else { return nil }
        }
        var common = stat()
        guard lstat(metadata.appendingPathComponent("commondir").path, &common) != 0,
              errno == ENOENT else { return nil }
        return metadata
    }

    static func ignored(_ url: URL) -> Bool? {
        let candidate = inspectionPath(url)
        guard case .found(let root) = repository(at: candidate) else { return nil }
        let result = runGit("/usr/bin/git", ["--no-optional-locks", "-c", "core.fsmonitor=false",
                                            "-C", root.path, "check-ignore", "-q", "--", candidate.path], 2)
        if result.status == 0 { return true }
        if result.status == 1 { return false }
        return nil
    }

    private static func runGit(_ executable: String, _ arguments: [String], _ timeout: TimeInterval) -> CommandResult {
        // The app may be launched from a terminal with a different repository
        // or index selected in its environment.
        let environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        return CommandRunner.run(executable, arguments, timeout: timeout, environment: environment)
    }

    static func failureReason(_ result: CommandResult) -> String {
        let text = result.output.lowercased()
        if text.contains("dubious ownership") || text.contains("unsafe repository") { return "Git rejected this repository’s ownership. Verify its owner before changing Git’s trust settings." }
        if text.contains("operation not permitted") || text.contains("permission denied") { return "macOS or filesystem permissions denied repository access. Check Files and Folders access and choose the repository folder again." }
        if text.contains("xcrun") || text.contains("developer tools") || text.contains("license") { return "Apple’s Git tools are unavailable or need setup. Open Xcode to finish its setup, then retry." }
        if text.contains("not a git repository") { return "Repository metadata changed or became unavailable during inspection." }
        if result.status == SIGTERM || result.status == SIGKILL { return "Git did not finish within the two-second inspection limit. Wait for repository activity to settle, then retry." }
        if result.status == -1 { return "Git could not be started on this Mac. Check that Apple’s command line developer tools are installed." }
        // Never put raw subprocess output (possibly filenames/configuration) into
        // the interface or transmit it to an AI provider.
        return "Git could not inspect the repository (status \(result.status)). Check repository health and access."
    }
}

extension GitInspection {
    /// Whether the repository containing `url` has uncommitted work.
    ///
    /// A build folder inside a repository with a clean tree is cheap to lose: the
    /// source that produced it is committed. The same folder inside a repository
    /// with uncommitted changes sits next to work that exists nowhere else, which
    /// is worth saying out loud before anyone selects it.
    ///
    /// Returns nil when the question does not apply or cannot be answered — no
    /// repository, no access, a timeout. An unanswered question is never reported
    /// as "clean".
    static func hasUncommittedChanges(near url: URL, run: (String, [String], TimeInterval) -> CommandResult = runGit) -> Bool? {
        guard case .found(let root) = repository(for: url) else { return nil }
        // Same hardening as `inspect`: no optional locks, no fsmonitor, literal
        // pathspecs, and a short timeout so a huge worktree cannot stall a scan.
        let arguments = [
            "--literal-pathspecs", "--no-optional-locks", "-c", "core.fsmonitor=false",
            "-C", root.path, "status", "--porcelain", "--untracked-files=no"
        ]
        let result = run("/usr/bin/git", arguments, 3)
        guard result.status == 0 else { return nil }
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
