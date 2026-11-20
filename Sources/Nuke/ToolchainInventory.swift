import CoreServices
import SwiftUI

enum ToolchainInventory {
    struct Installation: Identifiable, Sendable {
        let name: String
        let url: URL
        let lastUsed: Date?
        var id: String { url.path }
        /// The version set as default; never suggested for removal.
        var isDefault = false
        /// The tool's own command to remove this version, when it has one.
        var uninstall: String? {
            let version = url.lastPathComponent
            let path = url.path
            if path.contains("/.nvm/versions/node/") { return "nvm uninstall " + version.replacingOccurrences(of: "v", with: "", options: .anchored) }
            if path.contains("/.rustup/toolchains/") { return "rustup toolchain uninstall " + version }
            if path.contains("/.pyenv/versions/") { return "pyenv uninstall " + version }
            if path.contains("/.rbenv/versions/") { return "rbenv uninstall " + version }
            if path.contains("/.fnm/") || path.contains("/fnm/node-versions/") { return "fnm uninstall " + version }
            return nil
        }
    }

    /// Default versions: nvm's `alias/default` and rustup's `default_toolchain`.
    /// Idea from Major Tom (MIT, Copyright (c) 2026 Tom Jordan).
    /// The Node your shell runs right now (the first `node` on the usual PATH),
    /// resolved through nvm's symlinks.
    static let activeNode: String? = {
        for directory in DevCleanups.searchPaths {
            let candidate = directory + "/node"
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        }
        return nil
    }()

    static func isDefault(_ url: URL, home: URL) -> Bool {
        let path = url.path, name = url.lastPathComponent
        if let active = activeNode, active.hasPrefix(url.resolvingSymlinksInPath().path + "/") { return true }
        if path.contains("/.nvm/versions/node/"),
           let alias = try? String(contentsOf: ToolLocations.nvmHome.appendingPathComponent("alias/default"), encoding: .utf8) {
            let wanted = alias.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "", options: .anchored)
            let have = name.replacingOccurrences(of: "v", with: "", options: .anchored)
            return !wanted.isEmpty && (have == wanted || have.hasPrefix(wanted + "."))
        }
        if path.contains("/.rustup/toolchains/"),
           let settings = try? String(contentsOf: home.appendingPathComponent(".rustup/settings.toml"), encoding: .utf8),
           let line = settings.split(separator: "\n").first(where: { $0.hasPrefix("default_toolchain") }) {
            let value = line.split(separator: "\"").dropFirst().first.map(String.init) ?? ""
            return !value.isEmpty && name.hasPrefix(value)
        }
        return false
    }

    static func inspect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        token: ScanCancellation) -> [Installation] {
        let locations: [(String, URL, String, String)] = [
            ("Node", home.appendingPathComponent(".nvm/versions/node"), "", "bin/node"),
            ("Node", home.appendingPathComponent(".fnm/node-versions"), "", "installation/bin/node"),
            ("Node", home.appendingPathComponent("Library/Application Support/fnm/node-versions"), "", "installation/bin/node"),
            ("Python", home.appendingPathComponent(".pyenv/versions"), "", "bin/python"),
            ("Python", URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions"), "", "bin/python3"),
            ("Ruby", home.appendingPathComponent(".rbenv/versions"), "", "bin/ruby"),
            ("Ruby", home.appendingPathComponent(".rvm/rubies"), "", "bin/ruby"),
            ("Rust", home.appendingPathComponent(".rustup/toolchains"), "", "bin/rustc"),
            ("Node", URL(fileURLWithPath: "/opt/homebrew/Cellar"), "node", "bin/node"),
            ("Python", URL(fileURLWithPath: "/opt/homebrew/Cellar"), "python", "bin/python3"),
            ("Ruby", URL(fileURLWithPath: "/opt/homebrew/Cellar"), "ruby", "bin/ruby"),
            ("Node", URL(fileURLWithPath: "/usr/local/Cellar"), "node", "bin/node"),
            ("Python", URL(fileURLWithPath: "/usr/local/Cellar"), "python", "bin/python3"),
            ("Ruby", URL(fileURLWithPath: "/usr/local/Cellar"), "ruby", "bin/ruby")
        ]

        var results: [Installation] = []
        var seen = Set<String>()
        for app in AppInventory.apps(roots: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")], token: token)
        where app.bundleID == "com.apple.dt.Xcode" {
            results.append(Installation(name: "Xcode " + app.version, url: app.url, lastUsed: app.lastOpened))
        }
        for (name, root, formula, binary) in locations {
            if token.cancelled { break }
            let roots = formula.isEmpty ? [root] : children(root).filter {
                $0.lastPathComponent == formula || $0.lastPathComponent.hasPrefix(formula + "@")
            }
            for folder in roots {
                for version in children(folder) {
                    if token.cancelled { return sorted(results) }
                    let executable = version.appendingPathComponent(binary)
                    guard FileManager.default.isExecutableFile(atPath: executable.path),
                          seen.insert(version.resolvingSymlinksInPath().path).inserted else { continue }
                    let lastUsed = MDItemCreateWithURL(kCFAllocatorDefault, executable as CFURL)
                        .flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
                    var installation = Installation(name: name + " " + version.lastPathComponent, url: version, lastUsed: lastUsed)
                    installation.isDefault = isDefault(version, home: home)
                    results.append(installation)
                }
            }
        }
        return sorted(results)
    }

    private static func children(_ root: URL) -> [URL] {
        let entries = try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return Array((entries ?? []).prefix(200)).filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
    }

    private static func sorted(_ values: [Installation]) -> [Installation] {
        values.sorted {
            let first = $0.lastUsed ?? .distantFuture
            let second = $1.lastUsed ?? .distantFuture
            return first == second ? ($0.name, $0.id) < ($1.name, $1.id) : first < second
        }
    }
}

struct ToolchainInventoryView: View {
    @Environment(AppModel.self) private var model
    @State private var installations: [ToolchainInventory.Installation]?
    @State private var cancellation: ScanCancellation?

    var body: some View {
        DisclosureGroup("Installed toolchains") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Xcode, Node, Python, Ruby, and Rust in common installation locations. Oldest recorded use appears first. Spotlight may have no last-used date, especially for command-line tools.")
                    .foregroundStyle(Theme.secondary)
                HStack {
                    Button("Inspect toolchains") { inspect() }.buttonStyle(QuietButton())
                        .disabled(cancellation != nil)
                    if let cancellation {
                        ProgressView().controlSize(.small)
                        Button("Stop") { cancellation.cancel() }.buttonStyle(HoverPlain())
                    }
                }
                if let installations {
                    if installations.isEmpty { Text("No toolchains found in the locations checked.") }
                    ForEach(installations) { tool in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tool.name).fontWeight(.semibold)
                                Text(tool.url.path).lineLimit(1).truncationMode(.middle).help(tool.url.path)
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            if let date = tool.lastUsed {
                                Text("Last used: \(date.formatted(date: .abbreviated, time: .omitted))")
                            } else { Text("Last used: Unknown") }
                            if tool.isDefault {
                                Text("Default or active · kept").foregroundStyle(Theme.green)
                            } else if let command = tool.uninstall {
                                Button("Copy uninstall command") {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
                                }.buttonStyle(HoverPlain()).foregroundStyle(Theme.orange).help(command)
                            }
                            Button("Show in Finder") { model.reveal(tool.url) }.buttonStyle(HoverPlain())
                        }
                    }
                }
            }.font(.system(size: 12)).padding(.vertical, 8)
        }.onDisappear { cancellation?.cancel() }
    }

    private func inspect() {
        let token = ScanCancellation()
        cancellation = token
        Task {
            let result = await DiskWork.run("Inspecting toolchains", cancellation: token) {
                ToolchainInventory.inspect(token: token)
            }
            if !token.cancelled { installations = result }
            cancellation = nil
        }
    }
}
