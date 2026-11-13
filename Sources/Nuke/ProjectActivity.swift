import Foundation

/// Heuristic, read-only mapping from running commands to measured project roots.
/// A match requires the project root path to appear in the process command; the
/// detector deliberately does not inspect process cwd or ports.
enum ProjectActivityDetector {
    static let developmentProcesses: Set<String> = [
        "node", "npm", "pnpm", "yarn", "bun", "deno", "vite", "next", "webpack",
        "python", "python3", "uvicorn", "gunicorn", "cargo", "rustc", "go",
        "swift", "xcodebuild", "dotnet", "java", "gradle", "mvn", "flutter", "dart",
        "ruby", "rails", "php", "deno"
    ]

    static func active(projects: [ProjectGroup], processes: [ProcessRow]) -> [String: [String]] {
        guard !projects.isEmpty, !processes.isEmpty else { return [:] }
        var result: [String: Set<String>] = [:]
        for project in projects {
            let root = project.root.standardizedFileURL.path
            guard !root.isEmpty, root != "/" else { continue }
            for process in processes {
                guard process.command.contains(root + "/") || process.command.hasSuffix(root) else { continue }
                result[project.id, default: []].insert(executableName(process.command))
            }
        }
        return result.mapValues { $0.sorted() }
    }

    static func activeWithPorts(projects: [ProjectGroup], ports: [ListeningPort], cwd: [Int32: String]) -> [String: [String]] {
        guard !projects.isEmpty, !ports.isEmpty else { return [:] }
        var result: [String: Set<String>] = [:]
        for port in ports {
            guard let directory = cwd[port.pid], !directory.isEmpty else { continue }
            for project in projects {
                let root = project.root.standardizedFileURL.path
                guard !root.isEmpty, root != "/" else { continue }
                guard directory == root || directory.hasPrefix(root + "/") else { continue }
                result[project.id, default: []].insert("\(port.process):\(port.port)")
            }
        }
        return result.mapValues { $0.sorted() }
    }

    static func isDevelopmentProcess(_ process: ProcessRow) -> Bool {
        developmentProcesses.contains(executableName(process.command))
    }

    static func activeWithProcessCWD(projects: [ProjectGroup], processes: [ProcessRow], cwd: [Int32: String]) -> [String: [String]] {
        guard !projects.isEmpty, !processes.isEmpty else { return [:] }
        var result: [String: Set<String>] = [:]
        for process in processes where isDevelopmentProcess(process) {
            guard let directory = cwd[process.pid], !directory.isEmpty else { continue }
            for project in projects {
                let root = project.root.standardizedFileURL.path
                guard !root.isEmpty, root != "/" else { continue }
                guard directory == root || directory.hasPrefix(root + "/") else { continue }
                result[project.id, default: []].insert(executableName(process.command))
            }
        }
        return result.mapValues { $0.sorted() }
    }

    static func executableName(_ command: String) -> String {
        let tokens = command.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return "process" }
        let name = URL(fileURLWithPath: first).lastPathComponent
        if name == "env", tokens.count > 1 { return URL(fileURLWithPath: tokens[1]).lastPathComponent }
        return name
    }

    static func summary(_ names: [String]) -> String {
        names.isEmpty ? "" : "Possibly active: " + names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " +\(names.count - 4)" : "")
    }
}

/// Projects nothing has touched in a long time.
///
/// The single most useful question on the Projects screen is not "which folder is
/// biggest?" but "which of these am I done with?". A project whose build output
/// has not changed in months is one whose dependencies and artifacts are almost
/// certainly dead weight, and the answer is already in the measurements.
///
/// This only describes; it never selects. Anything it names still goes through
/// the same review as any other candidate.
enum StaleProjects {
    struct Sweep: Sendable {
        let groups: [ProjectGroup]
        let bytes: Int64
        let months: Int
        var count: Int { groups.count }
        var isEmpty: Bool { groups.isEmpty }
    }

    /// The most recent modification across a project's measured entries. A
    /// project with no dated entries is not considered stale: unknown is not old.
    static func lastTouched(_ group: ProjectGroup) -> Date? {
        // The later of read and write across the project's measured entries. A
        // dependency folder read by every build but never written is in use, and
        // judging it by modification time alone would call it dormant.
        group.entries.compactMap(\.item.lastTouched).max()
    }

    /// Projects whose newest measured entry predates `months` ago, largest first.
    /// `activeRoots` are excluded outright — something running there is decisive
    /// regardless of file dates.
    static func sweep(
        _ groups: [ProjectGroup],
        months: Int = 6,
        now: Date = Date(),
        activeRoots: Set<String> = []
    ) -> Sweep {
        let cutoff = now.addingTimeInterval(-Double(months) * 30 * 86_400)
        let stale = groups.filter { group in
            guard !activeRoots.contains(group.root.standardizedFileURL.path) else { return false }
            guard let touched = lastTouched(group) else { return false }
            return touched < cutoff && group.size > 0
        }.sorted { $0.size > $1.size }
        return Sweep(groups: stale, bytes: stale.reduce(0) { $0 + $1.size }, months: months)
    }
}
