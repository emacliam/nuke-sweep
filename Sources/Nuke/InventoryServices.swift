import Foundation
import AppKit
import Darwin

enum InventoryService {
    static func children(_ root: URL, notes: inout [String]) -> [URL] {
        var info = stat()
        if lstat(root.path, &info) != 0 {
            if errno != ENOENT && errno != ENOTDIR { notes.append("Could not inspect \(root.path): \(String(cString: strerror(errno))). Coverage is partial.") }
            return []
        }
        do { return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch { notes.append("Could not read \(root.path): \(error.localizedDescription). Coverage is partial."); return [] }
    }
    static func measure(_ url: URL, token: ScanCancellation = ScanCancellation()) -> DiskItem? {
        var s = stat(); guard lstat(url.path, &s) == 0 else { return nil }
        let dir = s.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        let link = s.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
        let r = dir ? DiskScanner.scan(url, cancellation: token) : nil
        return DiskItem(url: url, size: r?.logical ?? Int64(s.st_size), allocated: r?.allocated ?? Int64(s.st_blocks) * 512, directory: dir, symlink: link, modified: Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec)), identity: FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino)), incomplete: r.map { $0.skipped > 0 || $0.limited } ?? false)
    }
    static func projects(_ root: URL, token: ScanCancellation = ScanCancellation()) -> [ProjectGroup] {
        let fm = FileManager.default
        var groups: [ProjectGroup] = [], seen = 0
        func visit(_ url: URL, depth: Int) {
            guard !token.cancelled, depth <= 3, seen < 500, groups.count < 40 else { return }; seen += 1
            guard let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
            let names = Set(children.map(\.lastPathComponent))
            let kind: String?
            if names.contains("package.json") { kind = "JavaScript / TypeScript" }
            else if names.contains("Cargo.toml") { kind = "Rust" }
            else if names.contains("Package.swift") || names.contains(where: { $0.hasSuffix(".xcodeproj") }) { kind = "Swift / Xcode" }
            else if names.contains("pyproject.toml") || names.contains("requirements.txt") { kind = "Python" }
            else if names.contains("build.gradle") || names.contains("build.gradle.kts") { kind = "Gradle" }
            else if names.contains("go.mod") { kind = "Go" }
            else { kind = nil }
            if let kind {
                var candidates = [String]()
                if kind == "JavaScript / TypeScript" { candidates = ["node_modules", ".next", ".nuxt", ".turbo", "dist", "build"] }
                if kind == "Rust" { candidates = ["target"] }
                if kind == "Swift / Xcode" { candidates = [".build", "DerivedData"] }
                if kind == "Python" { candidates = [".venv", "venv", ".pytest_cache", ".mypy_cache", "__pycache__"] }
                if kind == "Gradle" { candidates = [".gradle", "build"] }
                let entries = candidates.compactMap { name -> InventoryEntry? in
                    guard let item = measure(url.appendingPathComponent(name), token: token), !item.symlink else { return nil }
                    let uncertain = name == "dist" || name == "build" || name == "venv"
                    return InventoryEntry(item: item, category: "Project artifacts", owner: url.lastPathComponent, explanation: uncertain ? "Name-based candidate. It may contain source or hand-edited files; inspect it before selection." : "Generated output or installed dependencies associated with the project marker. Stop its tools first; rebuilding or reinstalling may be required.")
                }
                groups.append(ProjectGroup(root: url, kind: kind, entries: entries))
            }
            for child in children where !["node_modules", "target", "build", "dist", "Pods", "venv"].contains(child.lastPathComponent) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true && values?.isSymbolicLink != true && child.pathExtension != "app" && child.pathExtension != "xcodeproj" { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return groups.sorted { $0.size > $1.size }
    }
    static func ai(home: URL = FileManager.default.homeDirectoryForCurrentUser, custom: [URL] = [], token: ScanCancellation = ScanCancellation()) -> InventoryReport {
        let roots = [("Ollama", ".ollama/models"), ("Hugging Face", ".cache/huggingface/hub"), ("Hugging Face", "Library/Caches/huggingface/hub"), ("LM Studio", ".lmstudio/models"), ("LM Studio", ".cache/lm-studio/models")]
        var report = InventoryReport()
        var seen = Set<String>()
        for (tool, url) in roots.map({ ($0.0, home.appendingPathComponent($0.1)) }) + custom.map({ ("Custom models", $0) }) {
            if token.cancelled { report.notes.append("Inspection stopped; coverage is partial."); break }
            guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
            var info = stat()
            if lstat(url.path, &info) != 0 {
                if tool == "Custom models" || (errno != ENOENT && errno != ENOTDIR) { report.notes.append("Could not inspect \(url.path): \(String(cString: strerror(errno))). Coverage is partial; choose the custom folder again if it moved.") }
                continue
            }
            guard let item = measure(url, token: token) else { report.notes.append("Could not measure \(url.path). Coverage is partial."); continue }
            if item.incomplete { report.notes.append("Incomplete measurement at \(url.path); some contents were unreadable or the scan limit was reached.") }
            let explanation = tool == "Custom models" ? "User-selected folder; model ownership is unverified. This chosen root is inventory-only. Use Storage to inspect and review individual descendants. Removing from the list does not delete files or revoke its folder permission." : "Known default location for \(tool). May be shared by several models. Download size/cost is unknown; removing it can require downloading models again. Custom locations require explicit folder selection."
            report.entries.append(InventoryEntry(item: item, category: "Local models", owner: tool, explanation: explanation, removable: tool != "Custom models"))
        }
        report.notes.append("Model ownership is inferred from default locations, not proof that a tool still uses them. Shared model blobs are not offered for individual removal.")
        return report
    }
    static func devices(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation = ScanCancellation()) -> InventoryReport {
        var report = InventoryReport()
        if token.cancelled { report.notes.append("Device inspection cancelled; results are partial."); return report }
        let roots = [("Xcode archive", "Library/Developer/Xcode/Archives"), ("Device backup", "Library/Application Support/MobileSync/Backup")]
        for (category, relative) in roots {
            let root = home.appendingPathComponent(relative)
            let children = self.children(root, notes: &report.notes)
            let candidates: [URL]
            if category == "Xcode archive" { candidates = children.filter { !$0.lastPathComponent.hasPrefix(".") }.flatMap { self.children($0, notes: &report.notes) }.filter { $0.pathExtension == "xcarchive" } }
            else { candidates = children.filter { !$0.lastPathComponent.hasPrefix(".") } }
            for url in candidates.prefix(150) {
                if token.cancelled { report.notes.append("Device inspection cancelled; results are partial."); return report }
                if let item = measure(url, token: token) {
                    report.entries.append(InventoryEntry(item: item, category: category, owner: category == "Xcode archive" ? "Xcode" : "Finder / MobileSync", explanation: category == "Xcode archive" ? "An archive may be needed for distribution, symbolication, or re-export. It is not a disposable build cache." : "A device backup can be the only copy of personal data. Review its identity and recovery needs before removal."))
                }
            }
            if candidates.count > 150 { report.notes.append("Showing only the first 150 \(category.lowercased()) locations.") }
        }
        if token.cancelled { report.notes.append("Device inspection cancelled; results are partial."); return report }
        let devices = CommandRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"], timeout: 20)
        if devices.status == 0, let json = try? JSONSerialization.jsonObject(with: Data(devices.output.utf8)) as? [String: Any], let sets = json["devices"] as? [String: [[String: Any]]] {
            for d in sets.values.flatMap({ $0 }).prefix(100) {
                if token.cancelled { report.notes.append("Device inspection cancelled; results are partial."); return report }
                guard let udid = d["udid"] as? String else { continue }
                let path = (d["dataPath"] as? String).map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/" + udid)
                if let item = measure(path, token: token) { report.entries.append(InventoryEntry(item: item, category: "Simulator device", owner: d["name"] as? String ?? udid, explanation: "State: \(d["state"] as? String ?? "unknown"). Manage devices through Xcode; deleting directories directly is not offered.", removable: false)) }
            }
        } else { report.notes.append("Simulator device listing unavailable. \(devices.output.prefix(200))") }
        if token.cancelled { report.notes.append("Device inspection cancelled; results are partial."); return report }
        let runtimes = CommandRunner.run("/usr/bin/xcrun", ["simctl", "list", "runtimes", "--json"], timeout: 20)
        if runtimes.status == 0, let json = try? JSONSerialization.jsonObject(with: Data(runtimes.output.utf8)) as? [String: Any], let list = json["runtimes"] as? [[String: Any]] {
            for d in list {
                let name = d["name"] as? String ?? "Runtime", version = d["version"] as? String ?? ""
                report.notes.append("Runtime: \(name) \(version) · \((d["isAvailable"] as? Bool) == true ? "available" : "unavailable") · manage through Xcode Settings → Components.")
            }
        } else { report.notes.append("Runtime inventory unavailable. Open Xcode Settings to review installed runtimes.") }
        return report
    }
}

enum AppInventory {
    static func apps(roots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")], token: ScanCancellation = ScanCancellation()) -> [InstalledApp] {
        var found: [InstalledApp] = []
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if token.cancelled { break }
                guard url.pathExtension == "app", (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                guard let b = Bundle(url: url), let id = b.bundleIdentifier else { continue }
                found.append(InstalledApp(url: url, name: b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent, bundleID: id, version: b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"))
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    static func related(_ app: InstalledApp, home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation = ScanCancellation()) -> InventoryReport {
        let id = app.bundleID
        guard !id.contains("/"), id != ".", id != ".." else { return InventoryReport(notes: ["Invalid bundle identifier; no related paths inferred."]) }
        var report = InventoryReport()
        if token.cancelled { return InventoryReport(notes: ["Inspection stopped."]) }
        if let item = InventoryService.measure(app.url, token: token) { report.entries.append(InventoryEntry(item: item, category: "Application", owner: app.name, explanation: "Application bundle. Quit this app before uninstalling it.")) }
        let candidates = [("Caches", "Library/Caches/" + id), ("Preferences", "Library/Preferences/" + id + ".plist"), ("Support files", "Library/Application Support/" + id), ("Logs", "Library/Logs/" + id), ("Startup component", "Library/LaunchAgents/" + id + ".plist")]
        for (kind, path) in candidates {
            if token.cancelled { break }
            if let item = InventoryService.measure(home.appendingPathComponent(path), token: token) { report.entries.append(InventoryEntry(item: item, category: kind, owner: "Candidate for " + app.name, explanation: "Exact bundle-identifier path match, not verified exclusive ownership. Inspect before selection; shared app data and group containers are excluded.")) }
        }
        report.notes = ["No items are selected automatically. Only exact bundle-identifier paths are suggested; app-name folders and shared containers are not inferred. Application data may contain documents or account state."]
        return report
    }
    static func leftovers(home: URL = FileManager.default.homeDirectoryForCurrentUser, installed: [InstalledApp], token: ScanCancellation = ScanCancellation()) -> InventoryReport {
        let ids = Set(installed.map(\.bundleID)), roots = ["Library/Caches", "Library/Preferences", "Library/Logs"]
        var report = InventoryReport()
        if installed.isEmpty { report.notes.append("No installed apps were available in the scanned roots. All ownership matches are uncertain.") }
        for relative in roots {
            let folder = home.appendingPathComponent(relative)
            for url in InventoryService.children(folder, notes: &report.notes).prefix(1000) {
                if token.cancelled { report.notes.append("Inspection stopped; results are partial."); return report }
                let id = url.pathExtension == "plist" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
                guard id.hasPrefix("com.") || id.hasPrefix("org.") || id.hasPrefix("io."), !id.hasPrefix("com.apple."), !ids.contains(id) else { continue }
                if let item = InventoryService.measure(url, token: token) { report.entries.append(InventoryEntry(item: item, category: "Unmatched app identifier", owner: id, explanation: "No exact identifier in the scanned Applications folders. An app elsewhere, helper, or shared vendor service may still use this item. This is not proof of an orphan.")) }
                if report.entries.count >= 100 { report.notes.append("Stopped at 100 unmatched candidates; inspect remaining items in Finder."); return report }
            }
        }
        report.notes.append("Applications outside /Applications and ~/Applications are not in this match. These candidates require manual ownership review.")
        return report
    }
}
