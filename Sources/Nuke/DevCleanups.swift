import SwiftUI
import NukeMetrics

/// Cleanups a developer tool does for itself.
///
/// A package manager's own cleaner knows which entries it still references and
/// fixes its bookkeeping afterwards, so it is preferred over moving its folder to
/// Trash. These remove permanently: each one is confirmed on its own, and the
/// exact command is shown first.
struct ToolCleaner: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let binaries: [String]
    /// Cache folder, relative to the home folder, measured to show what it holds.
    let cache: String
    let arguments: [String]
    let effect: String

    static let all: [ToolCleaner] = [
        .init(id: "npm", name: "npm cache", binaries: ["npm"], cache: ".npm/_cacache",
              arguments: ["cache", "clean", "--force"], effect: "Packages download again on the next install."),
        .init(id: "pnpm", name: "pnpm store", binaries: ["pnpm"], cache: "Library/pnpm/store",
              arguments: ["store", "prune"], effect: "Removes only packages no project references."),
        .init(id: "yarn", name: "Yarn cache", binaries: ["yarn"], cache: "Library/Caches/Yarn",
              arguments: ["cache", "clean"], effect: "Packages download again on the next install."),
        .init(id: "bun", name: "Bun cache", binaries: ["bun"], cache: ".bun/install/cache",
              arguments: ["pm", "cache", "rm"], effect: "Packages download again on the next install."),
        .init(id: "pip", name: "pip cache", binaries: ["pip3", "pip"], cache: "Library/Caches/pip",
              arguments: ["cache", "purge"], effect: "Wheels download again on the next install."),
        .init(id: "uv", name: "uv cache", binaries: ["uv"], cache: ".cache/uv",
              arguments: ["cache", "clean"], effect: "Packages download again on the next install."),
        .init(id: "go", name: "Go build cache", binaries: ["go"], cache: "Library/Caches/go-build",
              arguments: ["clean", "-cache"], effect: "The next build compiles from scratch."),
        .init(id: "brew", name: "Homebrew downloads", binaries: ["brew"], cache: "Library/Caches/Homebrew",
              arguments: ["cleanup", "--prune=all"], effect: "Removes old versions and downloaded installers."),
    ]

    var command: String { ([binaries[0]] + arguments).joined(separator: " ") }
}

struct ToolCacheFinding: Identifiable, Sendable {
    var id: String { tool.id }
    let tool: ToolCleaner
    let executable: String
    let size: Int64
}

/// A linked Git worktree with nothing in it that exists only here.
struct StaleWorktree: Identifiable, Sendable {
    var id: String { path }
    let repository: String
    let path: String
    let branch: String
    let size: Int64
}

enum DevCleanups {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var searchPaths: [String] {
        var paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin", "/usr/bin",
                     home.appendingPathComponent(".bun/bin").path, home.appendingPathComponent(".local/bin").path,
                     home.appendingPathComponent(".volta/bin").path, home.appendingPathComponent(".cargo/bin").path]
        // nvm keeps each Node version in its own folder; the newest is the likeliest default.
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            paths += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
                .map { nvm.appendingPathComponent($0).appendingPathComponent("bin").path }
        }
        return paths
    }

    static func locate(_ tool: ToolCleaner) -> String? {
        for binary in tool.binaries {
            for directory in searchPaths {
                let path = directory + "/" + binary
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Measures one tool's cache. Nil when the tool or its cache is absent.
    static func measure(_ tool: ToolCleaner, token: ScanCancellation) -> ToolCacheFinding? {
        let cache = home.appendingPathComponent(tool.cache)
        guard FileManager.default.fileExists(atPath: cache.path), let executable = locate(tool) else { return nil }
        let scan = DiskScanner.scan(cache, cancellation: token, limit: 400_000, deadline: Date().addingTimeInterval(20))
        return ToolCacheFinding(tool: tool, executable: executable, size: scan.allocated)
    }

    static func run(_ finding: ToolCacheFinding) -> CommandResult {
        var environment = ProcessInfo.processInfo.environment
        // npm and friends are scripts that look for node beside them.
        environment["PATH"] = ([URL(fileURLWithPath: finding.executable).deletingLastPathComponent().path] + searchPaths).joined(separator: ":")
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        return CommandRunner.run(finding.executable, finding.tool.arguments, timeout: 300, environment: environment)
    }

    // MARK: Worktrees

    static let git = "/usr/bin/git"

    /// Linked worktrees of `repository` that are clean and whose commits exist
    /// elsewhere: pushed to their upstream, or merged into the main checkout.
    /// Anything Git cannot answer for is left out, never offered.
    static func staleWorktrees(in repository: URL, token: ScanCancellation) -> [StaleWorktree] {
        let list = CommandRunner.run(git, ["-C", repository.path, "worktree", "list", "--porcelain"], timeout: 10)
        guard list.status == 0 else { return [] }
        var found: [StaleWorktree] = []
        let blocks = list.output.components(separatedBy: "\n\n").dropFirst() // the first is the main checkout
        for block in blocks where !token.cancelled {
            let lines = block.split(separator: "\n").map(String.init)
            guard let path = lines.first(where: { $0.hasPrefix("worktree ") }).map({ String($0.dropFirst(9)) }),
                  !lines.contains(where: { $0.hasPrefix("locked") || $0 == "bare" }),
                  let branchRef = lines.first(where: { $0.hasPrefix("branch ") }).map({ String($0.dropFirst(7)) }),
                  FileManager.default.fileExists(atPath: path) else { continue }
            let branch = branchRef.replacingOccurrences(of: "refs/heads/", with: "")
            let status = CommandRunner.run(git, ["-C", path, "status", "--porcelain", "--untracked-files=normal"], timeout: 15)
            guard status.status == 0, status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard commitsAreSafe(worktree: path, repository: repository.path, branch: branch) else { continue }
            let size = DiskScanner.scan(URL(fileURLWithPath: path), cancellation: token, limit: 200_000,
                                        deadline: Date().addingTimeInterval(15)).allocated
            found.append(StaleWorktree(repository: repository.path, path: path, branch: branch, size: size))
        }
        return found
    }

    private static func commitsAreSafe(worktree: String, repository: String, branch: String) -> Bool {
        let upstream = CommandRunner.run(git, ["-C", worktree, "rev-list", "--count", "@{upstream}..HEAD"], timeout: 10)
        if upstream.status == 0 { return upstream.output.trimmingCharacters(in: .whitespacesAndNewlines) == "0" }
        // No upstream: safe only when the main checkout's branch already contains it.
        let merged = CommandRunner.run(git, ["-C", repository, "merge-base", "--is-ancestor", "refs/heads/" + branch, "HEAD"], timeout: 10)
        return merged.status == 0
    }

    /// Plain `git worktree remove`, without --force: Git itself refuses a
    /// worktree that gained changes since it was checked. The branch is kept.
    static func remove(_ worktree: StaleWorktree) -> CommandResult {
        CommandRunner.run(git, ["-C", worktree.repository, "worktree", "remove", worktree.path], timeout: 60)
    }
}

@MainActor @Observable final class DevCleanupState {
    var tools: [ToolCacheFinding] = []
    var worktrees: [StaleWorktree] = []
    var measuring = false
    var running: String?
    var lastOutcome: String?
    private var token = ScanCancellation()

    /// Every tool and every repository is measured as its own job, so the
    /// slowest one never holds up the rest.
    func refresh(repositories: [URL]) {
        token.cancel(); let token = ScanCancellation(); self.token = token
        measuring = true
        Task {
            async let tools: [ToolCacheFinding] = withTaskGroup(of: ToolCacheFinding?.self) { group in
                for tool in ToolCleaner.all {
                    group.addTask { await DiskWork.run("Measuring \(tool.name)", cancellation: token) { DevCleanups.measure(tool, token: token) } }
                }
                var found: [ToolCacheFinding] = []
                for await result in group { if let result { found.append(result) } }
                return found
            }
            async let trees: [StaleWorktree] = withTaskGroup(of: [StaleWorktree].self) { group in
                for repository in repositories {
                    group.addTask { await DiskWork.run("Checking worktrees", lane: .interactive, cancellation: token) { DevCleanups.staleWorktrees(in: repository, token: token) } }
                }
                var found: [StaleWorktree] = []
                for await result in group { found += result }
                return found
            }
            let (foundTools, foundTrees) = await (tools, trees)
            guard !token.cancelled else { return }
            self.tools = foundTools.filter { $0.size > 50_000_000 }.sorted { $0.size > $1.size }
            self.worktrees = foundTrees.sorted { $0.size > $1.size }
            measuring = false
        }
    }
}

/// Repositories worth asking about worktrees: the measured projects' roots
/// that are Git checkouts.
@MainActor func devCleanupRepositories(_ features: FeatureModel) -> [URL] {
    var seen = Set<String>()
    return features.projects.map(\.root).filter { root in
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) && seen.insert(root.path).inserted
    }
}

struct DevCleanupPanel: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var state = DevCleanupState()
    @State private var confirmTool: ToolCacheFinding?
    @State private var confirmTree: StaleWorktree?
    @State private var lastLive = Date.distantPast

    var body: some View {
        Group {
            if !state.tools.isEmpty || !state.worktrees.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Let your developer tools clean up after themselves").font(.system(size: 15, weight: .semibold))
                            Text("Each tool's own cleaner knows what it still needs. These remove permanently, so each one asks first.")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 0) {
                            ForEach(state.tools) { finding in
                                row(finding.tool.name, finding.tool.effect, detail: finding.tool.command, path: DevCleanups.home.appendingPathComponent(finding.tool.cache).path, size: finding.size,
                                    button: "Clear") { confirmTool = finding }
                                Divider()
                            }
                            ForEach(state.worktrees) { tree in
                                row("Worktree · \(tree.branch)", "Clean, and its commits exist elsewhere. The branch is kept.",
                                    detail: tree.path, path: tree.path, size: tree.size, button: "Remove") { confirmTree = tree }
                                Divider()
                            }
                        }
                        if let outcome = state.lastOutcome {
                            Text(verbatim: outcome).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .task(id: features.projects.count) { state.refresh(repositories: devCleanupRepositories(features)) }
        // Re-measure when a tool cache or a listed worktree changes on disk,
        // at most twice a minute, so the sizes here stay true.
        .onReceive(NotificationCenter.default.publisher(for: .nukeFilesChanged)) { note in
            guard state.running == nil, !state.measuring, Date().timeIntervalSince(lastLive) > 30 else { return }
            let all = note.userInfo?["all"] as? Bool ?? true
            let paths = note.userInfo?["paths"] as? Set<String> ?? []
            let record = ScanReuse(remembered: [:], changed: Array(paths))
            let watched = ToolCleaner.all.map { DevCleanups.home.appendingPathComponent($0.cache).path } + state.worktrees.map(\.path)
            guard !all, watched.contains(where: { record.dirty($0) }) else { return }
            lastLive = Date()
            state.refresh(repositories: devCleanupRepositories(features))
        }
        .confirmationDialog(confirmTool.map { "Clear \($0.tool.name)?" } ?? "", isPresented: Binding(get: { confirmTool != nil }, set: { if !$0 { confirmTool = nil } }), presenting: confirmTool) { finding in
            Button("Run \(finding.tool.command)", role: .destructive) { runTool(finding) }
        } message: { finding in
            Text("\(finding.tool.effect) This does not go to Trash and cannot be undone.")
        }
        .confirmationDialog(confirmTree.map { "Remove the \($0.branch) worktree?" } ?? "", isPresented: Binding(get: { confirmTree != nil }, set: { if !$0 { confirmTree = nil } }), presenting: confirmTree) { tree in
            Button("Remove worktree", role: .destructive) { removeTree(tree) }
        } message: { tree in
            Text("Runs git worktree remove on \(tree.path). Git refuses if anything changed since this check. The branch \(tree.branch) stays in the repository.")
        }
    }

    private func row(_ title: String, _ effect: String, detail: String, path: String, size: Int64, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 12, weight: .semibold))
                Text(verbatim: effect).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Text(verbatim: detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(verbatim: bytes(size)).font(.system(size: 13, weight: .medium)).monospacedDigit()
            Button { model.reveal(URL(fileURLWithPath: path)) } label: { Image(systemName: "folder") }
                .buttonStyle(HoverPlain()).foregroundStyle(Theme.secondary).help("Show in Finder")
            Button(button, action: action).buttonStyle(QuietButton())
                .disabled(state.running != nil || model.actionBusy)
        }
        .padding(.vertical, 9)
    }

    private func runTool(_ finding: ToolCacheFinding) {
        state.running = finding.id
        Task {
            let before = MachineService.snapshot().freeDisk
            let result = await DiskWork.run("Running \(finding.tool.command)", lane: .interactive) { DevCleanups.run(finding) }
            let after = MachineService.snapshot().freeDisk
            state.running = nil
            let freed = max(0, (after ?? 0) - (before ?? 0))
            state.lastOutcome = result.status == 0
                ? "\(finding.tool.command) finished. About \(bytes(freed)) more is free."
                : "\(finding.tool.command) failed: \(result.output.suffix(300))"
            model.refreshResources()
            model.record("Tool cleanup", detail: "\(finding.tool.command) · status \(result.status) · freed about \(bytes(freed))")
            state.refresh(repositories: devCleanupRepositories(features))
        }
    }

    private func removeTree(_ tree: StaleWorktree) {
        state.running = tree.id
        Task {
            let result = await DiskWork.run("Removing worktree", lane: .interactive) { DevCleanups.remove(tree) }
            state.running = nil
            state.lastOutcome = result.status == 0
                ? "Removed the \(tree.branch) worktree. The branch is still in the repository."
                : "Git did not remove it: \(result.output.suffix(300))"
            model.refreshResources()
            model.record("Worktree removed", detail: "\(tree.path) · status \(result.status)")
            state.refresh(repositories: devCleanupRepositories(features))
        }
    }
}
