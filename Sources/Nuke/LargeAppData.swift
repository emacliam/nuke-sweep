import Foundation
import Darwin

enum LargeAppData {
    struct Group: Identifiable, Sendable {
        let name: String
        let guidance: String
        let bytes: Int64?
        let partial: Bool
        var id: String { name }
    }

    static func inspect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        token: ScanCancellation = ScanCancellation()) -> [Group] {
        let home = home.resolvingSymlinksInPath().standardizedFileURL
        let deadline = Date().addingTimeInterval(24)
        let locations: [(String, [String], String)] = [
            ("Steam", ["Library/Application Support/Steam/steamapps"],
             "In Steam, open Settings → Storage and review installed games by library."),
            ("Telegram", ["Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram", "Library/Application Support/Telegram Desktop"],
             "In Telegram, open Settings → Data and Storage → Storage Usage to review cached media."),
            ("WhatsApp", ["Library/Group Containers/group.net.whatsapp.WhatsApp.shared", "Library/Containers/net.whatsapp.WhatsApp/Data/Library/Application Support"],
             "In WhatsApp, use its storage manager where available to review large media and chats."),
            ("Slack", ["Library/Application Support/Slack", "Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"],
             "In Slack, look for Help → Troubleshooting → Clear Cache and Restart."),
            ("Podcasts", ["Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache"],
             "In Podcasts, open Downloads and choose Remove Download for episodes you no longer need offline."),
            ("Music", ["Music/Music/Media", "Music/iTunes/iTunes Media"],
             "In Music, review Downloaded items and choose Remove Download where available. Imported files can also be stored here."),
            ("Mail", ["Library/Mail"],
             "In Mail, review messages and attachments using Mail’s own controls. Check the account’s retention and sync settings before removing anything."),
            ("Messages", ["Library/Messages/Attachments"],
             "In Messages, open a conversation’s info panel to review its attachments. Deletions can sync across devices.")
        ]
        let images = DockerInspection.localDisks(home: home)
        let docker = Group(name: "Docker Desktop",
                           guidance: "Use Docker Desktop’s Images, Containers and Volumes views to review usage. Its disk image can hold databases and other persistent data.",
                           bytes: images.isEmpty ? nil : images.reduce(0) { $0 + $1.allocated },
                           partial: images.isEmpty)
        return [docker] + locations.map { name, paths, guidance in
            var total: Int64?
            var partial = false
            for path in paths {
                guard !token.cancelled, Date() < deadline else { partial = true; break }
                let url = home.appendingPathComponent(path)
                var info = stat()
                guard lstat(url.path, &info) == 0 else {
                    if errno != ENOENT && errno != ENOTDIR { partial = true }
                    continue
                }
                let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path == url.standardizedFileURL.path,
                      info.st_mode & S_IFMT == S_IFDIR else { partial = true; continue }
                let scan = DiskScanner.scan(url, cancellation: token, limit: 20_000,
                                            deadline: min(deadline, Date().addingTimeInterval(3)))
                total = (total ?? 0) + scan.allocated
                partial = partial || scan.limited || scan.skipped > 0 || token.cancelled
            }
            return Group(name: name, guidance: guidance, bytes: total, partial: partial)
        }
    }
}
