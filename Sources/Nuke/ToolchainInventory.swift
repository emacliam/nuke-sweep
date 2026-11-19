import CoreServices
import SwiftUI

enum ToolchainInventory {
    struct Installation: Identifiable, Sendable {
        let name: String
        let url: URL
        let lastUsed: Date?
        var id: String { url.path }
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
                    results.append(Installation(name: name + " " + version.lastPathComponent,
                                                url: version, lastUsed: lastUsed))
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
