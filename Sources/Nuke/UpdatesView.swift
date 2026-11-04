import SwiftUI
import AppKit

struct PublicRelease: Decodable, Sendable {
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    var verifiedURL: URL? {
        guard !draft, !prerelease, let url = URL(string: html_url), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.port == nil, url.path == "/emacliam/nuke-sweep/releases/tag/" + tag_name else { return nil }
        return url
    }
    static func components(_ version: String) -> [Int]? {
        let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    func newer(than installed: String) -> Bool? {
        guard verifiedURL != nil, let remote = Self.components(tag_name), let local = Self.components(installed) else { return nil }
        return local.lexicographicallyPrecedes(remote)
    }
}
@MainActor final class UpdateChecker: ObservableObject {
    @Published var checking = false
    @Published var note = "Check the public GitHub release when you choose. No checks run automatically."
    @Published var releaseURL: URL?
    static var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.2" }
    func check() {
        guard !checking else { return }; checking = true; releaseURL = nil
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/emacliam/nuke-sweep/releases/latest")!)
                request.timeoutInterval = 15; request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { note = "Could not read the latest release. Try again later or visit the releases page."; return }
                let release = try JSONDecoder().decode(PublicRelease.self, from: data)
                guard let newer = release.newer(than: Self.installed), let url = release.verifiedURL else { note = "The release response could not be verified. Check the releases page manually."; return }
                releaseURL = url
                note = newer ? "Nuke Sweep \(release.tag_name) is available. Read the release notes and download the signed app." : "Installed: \(Self.installed). Latest public release: \(release.tag_name). No newer public version is available."
            } catch { note = "Update check failed: \(error.localizedDescription) Try again when connected." }
        }
    }
}
struct UpdatesView: View {
    @StateObject private var checker = UpdateChecker()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nuke Sweep \(UpdateChecker.installed)").font(.system(size: 18, weight: .semibold))
            Text(checker.checking ? "Checking the public release…" : checker.note).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack {
                Button("Check for updates") { checker.check() }.buttonStyle(PrimaryButton()).disabled(checker.checking)
                Button("Open releases") { NSWorkspace.shared.open(checker.releaseURL ?? URL(string: "https://github.com/emacliam/nuke-sweep/releases")!) }.buttonStyle(QuietButton())
            }
            Notice(text: "Downloads and installation remain under your control. This check contacts GitHub; it does not upload scans or file paths.", symbol: "info.circle")
        }
    }
}
