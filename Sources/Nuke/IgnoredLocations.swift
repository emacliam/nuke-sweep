import SwiftUI

enum IgnoredLocations {
    static let key = "nuke.ignoredLocations"
    static var paths: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func contains(_ url: URL, in paths: Set<String>) -> Bool {
        guard !paths.isEmpty else { return false }
        var path = url.standardizedFileURL.path
        while path != "/" && !path.isEmpty {
            if paths.contains(path) { return true }
            path = (path as NSString).deletingLastPathComponent
        }
        return paths.contains("/")
    }

    static func overlaps(_ url: URL, in paths: Set<String>) -> Bool {
        contains(url, in: paths) || paths.contains { $0.hasPrefix(url.standardizedFileURL.path == "/" ? "/" : url.standardizedFileURL.path + "/") }
    }

    static func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized.path != "/" else { return }
        let resolved = standardized.resolvingSymlinksInPath()
        UserDefaults.standard.set(paths.union([resolved.path]).sorted(), forKey: key)
    }
}

struct IgnoredLocationsView: View {
    @Environment(AppModel.self) private var model
    @State private var paths = IgnoredLocations.paths.sorted()

    var body: some View {
        DisclosureGroup("Ignored locations") {
            Text("Ignored files and folders are skipped by storage scans and protected from reviewed cleanup.")
                .foregroundStyle(Theme.secondary)
            if paths.isEmpty { Text("Ignore a file or folder from its details in Browse.") }
            ForEach(paths, id: \.self) { path in
                HStack {
                    Text(verbatim: path).textSelection(.enabled)
                    Spacer()
                    Button("Stop ignoring") {
                        paths = IgnoredLocations.paths.subtracting([path]).sorted()
                        UserDefaults.standard.set(paths, forKey: IgnoredLocations.key)
                        model.refreshAfterMutation()
                    }.buttonStyle(QuietButton())
                }
            }
        }.onAppear { paths = IgnoredLocations.paths.sorted() }
    }
}
