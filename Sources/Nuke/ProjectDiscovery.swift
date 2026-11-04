import Foundation
import Darwin

struct ProjectDiscoveryReport: Sendable {
    var projects: [ProjectGroup] = []
    var directories = 0
    var limited = false
    var skipped = 0
    var note: String {
        "\(directories) folders inspected · \(projects.count) workspaces with build/dependency folders" + (limited ? " · partial: search limit or cancellation reached" : "") + (skipped > 0 ? " · \(skipped) unreadable locations" : "")
    }
}
enum ProjectDiscovery {
    static let artifactNames: Set<String> = ["node_modules", ".next", ".nuxt", ".svelte-kit", ".turbo", "dist", "build", "target", ".build", "DerivedData", ".venv", "venv", ".pytest_cache", ".mypy_cache", "__pycache__", "Pods", "coverage"]
    static func scan(_ root: URL, token: ScanCancellation, maxDirectories: Int = 10_000, maxDepth: Int = 12, budget: TimeInterval = 90) -> ProjectDiscoveryReport {
        var report = ProjectDiscoveryReport(), namesVisited = 0, measuredEntries = 0
        let deadline = Date().addingTimeInterval(budget)
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { report.skipped = 1; return report }
        func withinBudget() -> Bool { !token.cancelled && Date() < deadline && report.directories <= maxDirectories && namesVisited < 100_000 && report.projects.count < 300 && measuredEntries < 1_000_000 }
        var stack: [(URL, Int)] = [(root, 0)]
        while let (directory, depth) = stack.popLast() {
            guard withinBudget(), report.directories < maxDirectories else { report.limited = true; break }
            report.directories += 1
            DiskWork.report(path: directory.path, visited: report.directories)
            var entries: [InventoryEntry] = [], next: [URL] = [], markers = Set<String>()
            do {
                let complete = try DirectoryEntries.visit(directory, shouldContinue: withinBudget) { child in
                    namesVisited += 1
                    let name = child.lastPathComponent
                    var info = stat()
                    guard lstat(child.path, &info) == 0 else { report.skipped += 1; return }
                    guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { markers.insert(name); return }
                    guard info.st_dev == rootInfo.st_dev else { report.skipped += 1; return }
                    if artifactNames.contains(name) {
                        let scan = DiskScanner.scan(child, cancellation: token, limit: min(250_000, max(1, 1_000_000 - measuredEntries)), deadline: deadline)
                        measuredEntries += scan.visited
                        let item = DiskItem(url: child, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)), identity: FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)), incomplete: scan.limited || scan.skipped > 0)
                        let advice = CleanupEvidenceService.rebuildAdvice(for: name.lowercased())
                        entries.append(.init(item: item, category: name == "node_modules" ? "Installed dependencies" : "Build/dependency candidate", owner: directory.lastPathComponent, explanation: "\(advice) Stop this workspace’s tools first. Name-based evidence; review checks for tracked files and protected contents."))
                        if scan.limited || scan.skipped > 0 { report.limited = true }
                    } else if !name.hasPrefix("."), !["Library", "Applications", "Photos Library.photoslibrary"].contains(name), !["app", "framework", "xcodeproj", "xcworkspace", "xcarchive"].contains(child.pathExtension.lowercased()) {
                        if depth < maxDepth { next.append(child) } else { report.limited = true }
                    }
                }
                if !complete { report.limited = true }
            } catch { report.skipped += 1 }
            if !entries.isEmpty {
                let kind = markers.contains("package.json") ? "JavaScript / TypeScript" : markers.contains("Cargo.toml") ? "Rust" : markers.contains("Package.swift") ? "Swift" : markers.contains("go.mod") ? "Go" : markers.contains("pyproject.toml") || markers.contains("requirements.txt") ? "Python" : "Workspace candidates"
                report.projects.append(.init(root: directory, kind: kind, entries: entries))
            }
            stack.append(contentsOf: next.sorted { $0.path > $1.path }.map { ($0, depth + 1) })
        }
        if token.cancelled { report.limited = true }
        report.projects.sort { $0.size > $1.size }
        return report
    }
}
