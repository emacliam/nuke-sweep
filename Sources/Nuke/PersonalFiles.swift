import Foundation
import Darwin

/// Finds space held by a person's own files rather than by developer tooling.
///
/// The rest of the check answers "what rebuilds itself?". On a Mac that is not
/// used for development that answer is small, and the space is somewhere else:
/// installers kept after the app was installed, the third download of the same
/// file, a year of screen recordings, an old phone backup.
///
/// None of this rebuilds itself, so the rules differ from the developer side:
///
/// - Nothing found here is ever selected for the person or cleaned
///   automatically. It is listed with the reason it was listed, and it only
///   moves through the same review as everything else.
/// - A finding says why it is here in terms a person can check: "Slack is
///   already installed", "same contents as report.pdf", "not opened for 412
///   days". Size alone is never the reason, except for very large files nobody
///   has touched in months.
/// - Photo libraries, mail, messages, cloud-synced folders and anything macOS
///   holds only as a cloud placeholder are not looked at.
/// - Folders that look like a project are not searched for personal files. Their
///   build and dependency folders are measured instead and handed to the same
///   ranking as the chosen code folder, so a stray checkout in Downloads or on
///   the Desktop is covered too.
enum PersonalFiles {
    /// How the thing comes back if it turns out to be needed.
    enum Recovery: Sendable {
        case redownload, regenerates, duplicate, onlyCopy

        var title: String {
            switch self {
            case .redownload: return String(localized: "Can be downloaded again")
            case .regenerates: return String(localized: "Rebuilt by the app that made it")
            case .duplicate: return String(localized: "Another copy stays in place")
            case .onlyCopy: return String(localized: "May be the only copy")
            }
        }
    }

    /// Raw values are identity: they key the selection and expansion state.
    enum Category: String, CaseIterable, Sendable {
        case installers, deviceSoftware, partialDownloads, repeatDownloads, extractedArchives
        case mailDownloads, editingCaches, logs
        case oldDownloads, screenRecordings, screenshots, video, audio
        case diskImages, deviceBackups, xcodeArchives, appPackages, largeForgotten

        var title: String {
            switch self {
            case .installers: return String(localized: "Installers")
            case .deviceSoftware: return String(localized: "iPhone and iPad software updates")
            case .partialDownloads: return String(localized: "Unfinished downloads")
            case .repeatDownloads: return String(localized: "Repeat downloads and copies")
            case .extractedArchives: return String(localized: "Archives already unpacked")
            case .mailDownloads: return String(localized: "Mail attachment copies")
            case .editingCaches: return String(localized: "Video editing render files")
            case .logs: return String(localized: "Logs and crash reports")
            case .oldDownloads: return String(localized: "Old downloads")
            case .screenRecordings: return String(localized: "Screen and meeting recordings")
            case .screenshots: return String(localized: "Old screenshots")
            case .video: return String(localized: "Large video")
            case .audio: return String(localized: "Large audio")
            case .diskImages: return String(localized: "Disk images and virtual machines")
            case .deviceBackups: return String(localized: "iPhone and iPad backups")
            case .xcodeArchives: return String(localized: "Xcode archives")
            case .appPackages: return String(localized: "Phone app packages")
            case .largeForgotten: return String(localized: "Large files not opened in months")
            }
        }

        var symbol: String {
            switch self {
            case .installers: return "shippingbox"
            case .deviceSoftware: return "iphone.and.arrow.forward"
            case .partialDownloads: return "arrow.down.circle.dotted"
            case .repeatDownloads: return "doc.on.doc"
            case .extractedArchives: return "archivebox"
            case .mailDownloads: return "paperclip"
            case .editingCaches: return "film.stack"
            case .logs: return "doc.text.magnifyingglass"
            case .oldDownloads: return "arrow.down.to.line"
            case .screenRecordings: return "record.circle"
            case .screenshots: return "camera.viewfinder"
            case .video: return "film"
            case .audio: return "waveform"
            case .diskImages: return "opticaldiscdrive"
            case .deviceBackups: return "iphone"
            case .xcodeArchives: return "hammer"
            case .appPackages: return "apps.iphone"
            case .largeForgotten: return "moon.zzz"
            }
        }

        var explanation: String {
            switch self {
            case .installers: return String(localized: "Disk images and packages are needed once, to install. The app keeps working without them.")
            case .deviceSoftware: return String(localized: "Firmware your Mac downloaded to update or restore a device. It is fetched again when needed.")
            case .partialDownloads: return String(localized: "Downloads that stopped part-way and have not been written to for days.")
            case .repeatDownloads: return String(localized: "Files whose contents were compared byte for byte with another file in the same folder. Only the extra copy is listed.")
            case .extractedArchives: return String(localized: "Compressed files with a folder of the same name beside them. Check the folder holds what you need before letting the archive go.")
            case .mailDownloads: return String(localized: "Copies Mail saves when you open an attachment. The attachment itself stays in the message.")
            case .editingCaches: return String(localized: "Render and media cache files. The editor recreates them from your original footage, which is not touched.")
            case .logs: return String(localized: "Log files and crash reports. Apps write new ones; old ones matter only if you are reporting a problem.")
            case .oldDownloads: return String(localized: "Things in Downloads that have not been opened or changed in three months.")
            case .screenRecordings: return String(localized: "Recordings of your screen or of meetings. Often kept by accident, but nothing can recreate them.")
            case .screenshots: return String(localized: "Screenshots older than a month. Small each, but they add up.")
            case .video: return String(localized: "Video files over 50 MB, outside any photo library.")
            case .audio: return String(localized: "Audio files over 100 MB, such as recordings and uncompressed exports.")
            case .diskImages: return String(localized: "Disk images and virtual machines. A virtual machine holds everything inside it.")
            case .deviceBackups: return String(localized: "Backups of a phone or tablet made on this Mac. Keep the latest one for any device you still use unless it also backs up to iCloud.")
            case .xcodeArchives: return String(localized: "Built apps kept for distribution and for reading crash reports. Keep the archive for any release still in use.")
            case .appPackages: return String(localized: "App packages for iPhone and Android (.ipa, .apk, .aab). If you built one yourself, this may be the only copy of that build.")
            case .largeForgotten: return String(localized: "Files over 500 MB that have not been opened or changed in six months.")
            }
        }

        var recovery: Recovery {
            switch self {
            case .installers, .deviceSoftware, .partialDownloads: return .redownload
            case .repeatDownloads, .extractedArchives, .mailDownloads: return .duplicate
            case .editingCaches, .logs: return .regenerates
            default: return .onlyCopy
            }
        }
    }

    struct Finding: Identifiable, Equatable, Sendable {
        let item: DiskItem
        let category: Category
        /// Why this was listed, in terms the person can check for themselves.
        let reason: String
        /// True when there is positive evidence the file is surplus: the app is
        /// installed, another copy was confirmed, the archive is unpacked.
        /// False when age or size is the only reason it is here.
        let redundant: Bool
        var id: String { item.id }
    }

    struct Report: Equatable, Sendable {
        var findings: [Finding] = []
        /// Build and dependency folders found in projects outside the chosen
        /// code folder. These go to the ranking, not to the personal list.
        var strayBuilds: [DiskItem] = []
        var strayProjectRoots: [String] = []
        var visited = 0
        /// The search stopped at its time, depth or entry limit.
        var limited = false
        /// Places macOS would not let the search read.
        var unreadable: [String] = []
        /// Files held only as cloud placeholders. Removing one frees nothing.
        var cloudOnly = 0
        /// Cloud-synced folders left alone on purpose.
        var syncFolders: [String] = []

        var totalBytes: Int64 { findings.reduce(0) { $0 + $1.item.size } }
        var redundantBytes: Int64 { findings.reduce(0) { $0 + ($1.redundant ? $1.item.size : 0) } }
        var categories: [Category] { Category.allCases.filter { category in findings.contains { $0.category == category } } }
        func findings(in category: Category) -> [Finding] { findings.filter { $0.category == category } }

        mutating func remove(paths: [String]) {
            let gone = Set(paths)
            findings.removeAll { gone.contains($0.item.url.path) }
            strayBuilds.removeAll { gone.contains($0.url.path) }
        }
    }

    struct Options: Sendable {
        var home = FileManager.default.homeDirectoryForCurrentUser
        var applicationFolders = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        /// Folders another scan already covers, such as the chosen code folder.
        var excluded: [URL] = []
        var now = Date()
        var budget: TimeInterval = 90
        var maxEntries = 600_000
        var maxDepth = 8
        /// How many bytes may be read to confirm that copies are identical.
        var compareBytes: Int64 = 6 * 1_024 * 1_024 * 1_024
        var measureStrayBuilds = true
    }

    // MARK: - Rules that need no filesystem

    static let partialExtensions: Set<String> = ["crdownload", "part", "partial", "download", "opdownload", "aria2", "!ut", "bc!", "tmp-download"]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "msi", "exe", "msix", "appx", "deb", "rpm", "appimage", "run"]
    static let archiveExtensions: Set<String> = ["zip", "tar", "tgz", "gz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "7z", "rar", "lz", "lzma", "cpgz"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "ts", "mts", "m2ts", "3gp", "vob", "mxf", "ogv", "f4v", "braw", "r3d", "divx"]
    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "flac", "caf", "m4a", "mp3", "ogg", "aac", "alac", "wma", "m4b", "opus"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "webp", "bmp"]
    static let diskImageExtensions: Set<String> = ["iso", "img", "vmdk", "vdi", "vhd", "vhdx", "qcow2", "qcow", "ova", "sparseimage", "toast", "cdr", "hdd", "raw"]
    /// Folders that are one thing to the person and hold a machine or image.
    static let machinePackages: Set<String> = ["utm", "pvm", "vmwarevm", "sparsebundle", "parallels", "vbox-prev"]
    /// Folders presented as a single file. They are not searched; opening a
    /// photo library or a project file to list its parts would only invite
    /// someone to remove a piece of it.
    static let opaquePackages: Set<String> = ["app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "aplibrary", "lrlibrary", "lrdata", "lrcat", "logicx", "band", "xcodeproj", "xcworkspace", "framework", "bundle", "plugin", "kext", "rtfd", "scriv", "sketch", "dsym", "playground", "pages", "numbers", "key", "epub", "itlp", "theater", "photosasset", "migratedphotolibrary", "tmbundle", "prefpane", "saver", "component", "vst", "vst3", "pkpass", "wdgt", "qlgenerator", "mdimporter", "docset", "lproj", "nib", "storyboardc", "xcassets", "appex", "xpc", "dext", "backupdb", "noindex"]
    /// Cloud-synced folders people commonly keep in their home folder. A file
    /// removed there is removed from every device, so they are left alone.
    static let syncFolderNames: Set<String> = ["dropbox", "google drive", "googledrive", "onedrive", "box", "box sync", "icloud drive", "icloud drive (archive)", "pcloud drive", "mega", "megasync", "sync", "nextcloud", "owncloud", "creative cloud files", "tresorit", "proton drive", "synology drive", "yandex.disk", "seafile"]

    static let screenshotPrefixes = ["screenshot ", "screen shot ", "cleanshot ", "simulator screenshot", "simulator screen shot", "capture d’écran", "capture d'écran", "bildschirmfoto", "captura de pantalla", "captura de ecrã", "captura de tela", "schermata ", "schermafbeelding", "skärmavbild", "skjermbilde", "skærmbillede", "näyttökuva", "zrzut ekranu", "снимок экрана", "スクリーンショット", "截屏", "截圖", "스크린샷", "snímek obrazovky", "ekran resmi", "monosnap", "shottr"]
    static let recordingPrefixes = ["screen recording ", "simulator screen recording", "bildschirmaufnahme", "enregistrement de l’écran", "enregistrement de l'écran", "grabación de pantalla", "registrazione schermo", "画面収録", "屏幕录制", "cleanshot ", "zoom_", "gmt20", "video1", "loom ", "obs ", "kap ", "recording ", "meeting recording", "teams meeting", "webex", "google meet", "untitled recording"]

    /// Days since the item was last read or written, or nil with no usable date.
    static func idleDays(_ touched: Date?, now: Date) -> Int? {
        guard let touched else { return nil }
        return max(0, Int(now.timeIntervalSince(touched) / 86_400))
    }

    /// Reduces a name to the letters and digits a person would recognise it by.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    private static let installerNoise: Set<String> = ["mac", "macos", "macosx", "osx", "darwin", "arm64", "arm", "aarch64", "x64", "x86", "amd64", "intel", "universal", "silicon", "apple", "m1", "m2", "installer", "install", "setup", "latest", "stable", "release", "beta", "full", "offline", "online", "signed", "notarized", "64", "32", "bit", "en", "us", "v", "for", "desktop", "app", "client"]

    /// The installed application an installer's file name points to, if any.
    ///
    /// Compares the leading words of the file name, with versions, platforms
    /// and words like "installer" removed, to installed application names. A
    /// match needs at least three characters, so "go.pkg" does not match
    /// "Google Chrome" and a stray "a.dmg" matches nothing.
    static func installedApp(for fileName: String, installed: [String: String]) -> String? {
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        let words = base.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }.map { String(String.UnicodeScalarView($0)) }
        // Everything from the first version number onwards describes the
        // build, not the application: "slack-4.36.140-macos" names "slack".
        func isVersion(_ word: String) -> Bool {
            let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
            return !digits.isEmpty && digits.allSatisfy(\.isNumber)
        }
        let named = Array(words.prefix { !isVersion($0) }).filter { !installerNoise.contains($0) }
        guard !named.isEmpty else { return nil }
        // Longest run of leading words first, so "Google Chrome Helper" prefers
        // an exact "Google Chrome" over a shorter accidental match.
        for count in stride(from: named.count, through: 1, by: -1) {
            let candidate = named.prefix(count).joined()
            guard candidate.count >= 3 else { continue }
            if let app = installed[candidate] { return app }
        }
        return nil
    }

    /// The name a copy was most likely made from: "report (2).pdf", "report
    /// copy.pdf" and "report 2.pdf" all point at "report.pdf". Only a
    /// suggestion; the contents are compared before anything is called a copy.
    static func originalName(ofCopy name: String) -> String? {
        let ns = name as NSString
        let ext = ns.pathExtension
        var stem = ns.deletingPathExtension
        func rebuilt(_ stem: String) -> String? {
            let trimmed = stem.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return ext.isEmpty ? trimmed : trimmed + "." + ext
        }
        // "name (2)"
        if stem.hasSuffix(")"), let open = stem.lastIndex(of: "(") {
            let inside = stem[stem.index(after: open)..<stem.index(before: stem.endIndex)]
            if !inside.isEmpty, inside.allSatisfy(\.isNumber), open > stem.startIndex, stem[stem.index(before: open)] == " " {
                return rebuilt(String(stem[..<open]))
            }
        }
        // "name copy", "name copy 3"
        if let range = stem.range(of: " copy", options: [.backwards, .caseInsensitive]) {
            let tail = stem[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if tail.isEmpty || tail.allSatisfy(\.isNumber) { return rebuilt(String(stem[..<range.lowerBound])) }
        }
        // "name 2" — what Finder writes when a name is taken.
        if let space = stem.lastIndex(of: " ") {
            let tail = stem[stem.index(after: space)...]
            if !tail.isEmpty, tail.count <= 2, tail.allSatisfy(\.isNumber), tail != "0", tail != "1" {
                stem = String(stem[..<space])
                return rebuilt(stem)
            }
        }
        return nil
    }

    /// The folder an archive would unpack into: "site.tar.gz" gives "site".
    static func unpackedName(ofArchive name: String) -> String? {
        var stem = (name as NSString).deletingPathExtension
        if (stem as NSString).pathExtension.lowercased() == "tar" { stem = (stem as NSString).deletingPathExtension }
        return stem.isEmpty ? nil : stem
    }

    static func isScreenshot(_ lowered: String) -> Bool { screenshotPrefixes.contains { lowered.hasPrefix($0) } }
    static func isRecording(_ lowered: String, parent: String) -> Bool {
        recordingPrefixes.contains { lowered.hasPrefix($0) } || ["zoom", "loom", "obs", "recordings", "screen recordings", "meetings"].contains(parent)
    }

    /// Everything the rules need to know about one file. Kept free of the
    /// filesystem so the rules can be tested without building a home folder.
    struct Facts {
        var name: String
        var size: Int64
        var touched: Date?
        var modified: Date?
        var parent = ""
        var inDownloads = false
        /// Other files in the same folder, by name, with their sizes.
        var siblingFiles: [String: Int64] = [:]
        var siblingFolders: Set<String> = []
        /// Normalised application name to the name as installed.
        var installed: [String: String] = [:]
        var now = Date()
    }

    struct Verdict: Equatable {
        var category: Category
        var reason: String
        var redundant: Bool
        /// Set for a suspected copy: the sibling whose contents must match.
        var compareWith: String?
    }

    private static func ago(_ days: Int?) -> String {
        guard let days else { return String(localized: "no usable date") }
        if days >= 730 { return String(format: String(localized: "%lld years"), days / 365) }
        if days >= 60 { return String(format: String(localized: "%lld months"), days / 30) }
        return String(format: String(localized: "%lld days"), days)
    }

    /// Decides whether a file belongs in the list, and under which heading.
    /// The order is the priority: a file is listed once, under the most
    /// specific reason that applies. `allowCopy` is false when a suspected copy
    /// turned out to differ and the file is being judged on its other merits.
    static func judge(_ facts: Facts, allowCopy: Bool = true) -> Verdict? {
        let lowered = facts.name.lowercased()
        let ext = (lowered as NSString).pathExtension
        let idle = idleDays(facts.touched, now: facts.now)
        let megabyte: Int64 = 1_000_000

        if partialExtensions.contains(ext) || lowered.hasPrefix("unconfirmed ") {
            // A download still being written is not clutter. Only one that has
            // sat unchanged for days is listed, and nothing else may claim it.
            guard let written = idleDays(facts.modified, now: facts.now), written >= 3 else { return nil }
            return Verdict(category: .partialDownloads, reason: String(format: String(localized: "Stopped part-way; last written %@ ago"), ago(written)), redundant: true)
        }
        if ext == "ipsw", facts.size >= megabyte {
            return Verdict(category: .deviceSoftware, reason: String(localized: "Device firmware; downloaded again when a device needs it"), redundant: true)
        }
        if installerExtensions.contains(ext), facts.size >= megabyte {
            if ["dmg", "pkg", "mpkg", "xip"].contains(ext), let app = installedApp(for: facts.name, installed: facts.installed) {
                return Verdict(category: .installers, reason: String(format: String(localized: "%@ is already installed"), app), redundant: true)
            }
            if ["exe", "msi", "msix", "appx", "deb", "rpm", "appimage"].contains(ext) {
                return Verdict(category: .installers, reason: String(localized: "An installer for another system; it cannot be installed on this Mac"), redundant: (idle ?? 0) >= 30)
            }
            return Verdict(category: .installers, reason: String(format: String(localized: "Installer not opened for %@"), ago(idle)), redundant: (idle ?? 0) >= 30)
        }
        if ["ipa", "apk", "aab"].contains(ext), facts.size >= megabyte {
            // Never called surplus: for someone who builds apps this is a
            // release build, and nothing else may hold that exact build.
            return Verdict(category: .appPackages, reason: String(format: String(localized: "App package, not opened for %@"), ago(idle)), redundant: false)
        }
        if allowCopy, facts.size >= 100_000, let original = originalName(ofCopy: facts.name),
           original != facts.name, facts.siblingFiles[original] == facts.size {
            return Verdict(category: .repeatDownloads, reason: String(format: String(localized: "Same contents as “%@” in the same folder"), original), redundant: true, compareWith: original)
        }
        if archiveExtensions.contains(ext), facts.size >= megabyte, let folder = unpackedName(ofArchive: facts.name), facts.siblingFolders.contains(folder) {
            return Verdict(category: .extractedArchives, reason: String(format: String(localized: "Already unpacked beside it as the folder “%@”"), folder), redundant: true)
        }
        if videoExtensions.contains(ext), facts.size >= 5 * megabyte, isRecording(lowered, parent: facts.parent) {
            return Verdict(category: .screenRecordings, reason: String(format: String(localized: "Recording, not opened for %@"), ago(idle)), redundant: false)
        }
        if imageExtensions.contains(ext), isScreenshot(lowered) {
            guard let idle, idle >= 30 else { return nil }
            return Verdict(category: .screenshots, reason: String(format: String(localized: "Screenshot, not opened for %@"), ago(idle)), redundant: false)
        }
        if videoExtensions.contains(ext), facts.size >= 50 * megabyte {
            return Verdict(category: .video, reason: String(format: String(localized: "Video, not opened for %@"), ago(idle)), redundant: false)
        }
        if audioExtensions.contains(ext), facts.size >= 100 * megabyte {
            return Verdict(category: .audio, reason: String(format: String(localized: "Audio, not opened for %@"), ago(idle)), redundant: false)
        }
        if diskImageExtensions.contains(ext), facts.size >= 50 * megabyte {
            return Verdict(category: .diskImages, reason: String(format: String(localized: "Disk image, not opened for %@"), ago(idle)), redundant: false)
        }
        if facts.inDownloads, facts.size >= 5 * megabyte, let idle, idle >= 90 {
            return Verdict(category: .oldDownloads, reason: String(format: String(localized: "In Downloads, not opened for %@"), ago(idle)), redundant: false)
        }
        if facts.size >= 500 * megabyte, let idle, idle >= 180 {
            return Verdict(category: .largeForgotten, reason: String(format: String(localized: "Not opened or changed for %@"), ago(idle)), redundant: false)
        }
        return nil
    }

    // MARK: - The search

    private struct Entry {
        let url: URL
        let name: String
        let info: stat
        var isDirectory: Bool { info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
        var isRegular: Bool { info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) }
        var modified: Date { Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)) }
        var accessed: Date { Date(timeIntervalSince1970: Double(info.st_atimespec.tv_sec)) }
        var touched: Date { max(modified, accessed) }
        /// macOS keeps only a placeholder; the contents live in the cloud.
        var cloudOnly: Bool { info.st_flags & UInt32(SF_DATALESS) != 0 }
        var identity: FileIdentity { FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino)) }
        var fileItem: DiskItem {
            DiskItem(url: url, size: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, directory: false, symlink: false,
                     modified: modified, accessed: accessed, identity: identity, incomplete: false)
        }
    }

    private struct PendingCopy {
        let entry: Entry
        let original: Entry
        let verdict: Verdict
        let fallback: Verdict?
    }

    /// Names of installed applications, normalised, mapped to how they appear.
    static func installedApplications(in folders: [URL]) -> [String: String] {
        var found: [String: String] = [:]
        func add(_ folder: URL, depth: Int) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names where !name.hasPrefix(".") {
                if name.hasSuffix(".app") {
                    let display = String(name.dropLast(4))
                    let key = normalized(display)
                    if key.count >= 3 { found[key] = display }
                } else if depth < 1 {
                    add(folder.appendingPathComponent(name), depth: depth + 1)
                }
            }
        }
        for folder in folders { add(folder, depth: 0) }
        return found
    }

    static func scan(_ options: Options = Options(), token: ScanCancellation = ScanCancellation()) -> Report {
        var report = Report()
        let home = options.home.standardizedFileURL
        let homePath = home.path
        let deadline = Date().addingTimeInterval(options.budget)
        var homeInfo = stat()
        guard lstat(homePath, &homeInfo) == 0 else { report.unreadable.append(homePath); return report }
        let device = homeInfo.st_dev
        let installed = installedApplications(in: options.applicationFolders)
        let excluded = options.excluded.map { $0.standardizedFileURL.path }
        // The folders a person treats as places rather than as projects. A stray
        // requirements.txt in Documents must not make Documents a project.
        let places = Set([homePath] + ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"].map { homePath + "/" + $0 })
        let downloads = homePath + "/Downloads"
        var pending: [PendingCopy] = []
        var strayProjects = 0
        let strayDeadline = Date().addingTimeInterval(min(45, options.budget / 2))

        func withinBudget() -> Bool {
            if token.cancelled || Date() > deadline || report.visited >= options.maxEntries || report.findings.count >= 25_000 {
                report.limited = true
                return false
            }
            return true
        }
        func isExcluded(_ path: String) -> Bool { excluded.contains { path == $0 || path.hasPrefix($0 + "/") } }
        func measured(_ entry: Entry, limit: Int = 150_000, seconds: TimeInterval = 12) -> DiskItem {
            let scan = DiskScanner.scan(entry.url, cancellation: token, limit: limit, deadline: min(deadline, Date().addingTimeInterval(seconds)))
            return DiskItem(url: entry.url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false,
                            modified: entry.modified, accessed: entry.accessed, identity: entry.identity, incomplete: scan.limited || scan.skipped > 0)
        }
        func add(_ item: DiskItem, _ category: Category, _ reason: String, redundant: Bool) {
            guard item.size > 0 else { return }
            report.findings.append(Finding(item: item, category: category, reason: reason, redundant: redundant))
        }
        func list(_ directory: URL) -> [Entry]? {
            var entries: [Entry] = []
            do {
                try DirectoryEntries.visit(directory, shouldContinue: withinBudget) { child in
                    report.visited += 1
                    if report.visited % 512 == 0 { DiskWork.report(path: child.path, visited: report.visited) }
                    var info = stat()
                    guard lstat(child.path, &info) == 0 else { return }
                    entries.append(Entry(url: child, name: child.lastPathComponent, info: info))
                }
            } catch {
                let code = (error as NSError).code
                if code == Int(EPERM) || code == Int(EACCES) { report.unreadable.append(directory.path) }
                return nil
            }
            return entries
        }
        /// Render files inside a Final Cut or iMovie library. The library itself
        /// is never offered; only the folders the editor rebuilds from footage.
        func renderFiles(in library: Entry) {
            func look(_ folder: URL, depth: Int) {
                guard depth <= 3, let entries = list(folder) else { return }
                for entry in entries where entry.isDirectory {
                    if entry.name == "Render Files" {
                        let item = measured(entry)
                        if item.size >= 10_000_000 {
                            add(item, .editingCaches, String(format: String(localized: "Render files in “%@”; the editor recreates them"), library.name), redundant: true)
                        }
                    } else if !entry.name.hasPrefix(".") { look(entry.url, depth: depth + 1) }
                }
            }
            look(library.url, depth: 0)
        }
        func strayBuilds(in project: URL) {
            guard options.measureStrayBuilds, strayProjects < 200, Date() < strayDeadline, !token.cancelled else {
                if options.measureStrayBuilds { report.limited = true }
                return
            }
            strayProjects += 1
            let remaining = max(1, min(12, strayDeadline.timeIntervalSinceNow))
            let found = ProjectDiscovery.scan(project, token: token, maxDirectories: 600, maxDepth: 6, budget: remaining)
            let items = found.projects.flatMap(\.entries).map(\.item).filter { $0.size > 0 }
            guard !items.isEmpty else { return }
            report.strayBuilds.append(contentsOf: items)
            report.strayProjectRoots.append(project.standardizedFileURL.path)
        }

        var stack: [(url: URL, depth: Int)] = [(home, 0)]
        while let (directory, depth) = stack.popLast() {
            guard withinBudget() else { break }
            guard let entries = list(directory) else { continue }
            let path = directory.standardizedFileURL.path
            let isPlace = places.contains(path)
            let inDownloads = path == downloads
            var files: [String: Entry] = [:]
            var folders = Set<String>()
            for entry in entries {
                if entry.isDirectory { folders.insert(entry.name) } else if entry.isRegular { files[entry.name] = entry }
            }
            // A project is not searched for personal files: a video in a
            // repository is an asset, not clutter. Its build folders are
            // measured instead, so a checkout outside the code folder counts.
            if !isPlace, entries.contains(where: { ReviewPlanner.isProjectMarker($0.name) }) {
                strayBuilds(in: directory)
                continue
            }
            let sizes = files.mapValues { Int64($0.info.st_size) }
            let parent = directory.lastPathComponent.lowercased()
            for entry in entries {
                guard withinBudget() else { break }
                let lowered = entry.name.lowercased()
                let ext = (lowered as NSString).pathExtension
                if entry.isDirectory {
                    guard entry.info.st_dev == device, !entry.name.hasPrefix("."), !isExcluded(entry.url.path) else { continue }
                    if depth == 0 {
                        if ["library", "applications"].contains(lowered) { continue }
                        if syncFolderNames.contains(lowered) || lowered.hasPrefix("onedrive") || lowered.hasPrefix("dropbox") {
                            report.syncFolders.append(entry.name); continue
                        }
                    }
                    if ext == "download" {
                        if let written = idleDays(entry.modified, now: options.now), written >= 3 {
                            add(measured(entry), .partialDownloads, String(format: String(localized: "Stopped part-way; last written %@ ago"), ago(written)), redundant: true)
                        }
                    } else if machinePackages.contains(ext) {
                        let item = measured(entry, limit: 50_000)
                        if item.size >= 50_000_000 {
                            add(item, .diskImages, String(format: String(localized: "Virtual machine or disk bundle, not opened for %@"), ago(idleDays(entry.touched, now: options.now))), redundant: false)
                        }
                    } else if ext == "xcarchive" {
                        add(measured(entry), .xcodeArchives, String(format: String(localized: "Archive last changed %@ ago"), ago(idleDays(entry.modified, now: options.now))), redundant: false)
                    } else if ext == "fcpbundle" || ext == "imovielibrary" {
                        renderFiles(in: entry)
                    } else if opaquePackages.contains(ext) {
                        continue
                    } else if inDownloads, let idle = idleDays(entry.touched, now: options.now), idle >= 90, !ReviewPlanner.looksLikeProjectRoot(entry.url) {
                        // An old folder in Downloads is offered whole: listing a
                        // thousand files from one forgotten download helps no one.
                        let item = measured(entry)
                        if item.size >= 5_000_000 {
                            add(item, .oldDownloads, String(format: String(localized: "Folder in Downloads, not opened for %@"), ago(idle)), redundant: false)
                        }
                    } else if depth < options.maxDepth {
                        stack.append((entry.url, depth + 1))
                    } else {
                        report.limited = true
                    }
                    continue
                }
                guard entry.isRegular, !entry.name.hasPrefix(".") else { continue }
                if entry.cloudOnly { report.cloudOnly += 1; continue }
                // Most files are small and of no interest. Deciding that from
                // the size first keeps the rules off the common case.
                let size = Int64(entry.info.st_size)
                guard size >= 100_000 || imageExtensions.contains(ext) || partialExtensions.contains(ext) else { continue }
                var siblings = sizes
                siblings[entry.name] = nil
                let facts = Facts(name: entry.name, size: size, touched: entry.touched, modified: entry.modified, parent: parent, inDownloads: inDownloads,
                                  siblingFiles: siblings, siblingFolders: folders, installed: installed, now: options.now)
                guard let verdict = judge(facts) else { continue }
                if let originalName = verdict.compareWith, let original = files[originalName] {
                    pending.append(PendingCopy(entry: entry, original: original, verdict: verdict, fallback: judge(facts, allowCopy: false)))
                } else {
                    add(entry.fileItem, verdict.category, verdict.reason, redundant: verdict.redundant)
                }
            }
        }

        // A name and a size suggest a copy; only the contents prove one. The
        // largest are compared first so the read budget goes where it matters.
        var compared: Int64 = 0
        for copy in pending.sorted(by: { $0.entry.info.st_size > $1.entry.info.st_size }) {
            let size = Int64(copy.entry.info.st_size)
            var same = false
            if !token.cancelled, Date() < deadline.addingTimeInterval(20), compared + size * 2 <= options.compareBytes {
                compared += size * 2
                same = (try? DuplicateFinder.sameContents(copy.entry.fileItem, copy.original.fileItem, token: token)) ?? false
            }
            if same {
                add(copy.entry.fileItem, copy.verdict.category, copy.verdict.reason, redundant: true)
            } else if let fallback = copy.fallback {
                add(copy.entry.fileItem, fallback.category, fallback.reason, redundant: fallback.redundant)
            }
        }

        knownLocations(home: home, options: options, token: token, deadline: deadline.addingTimeInterval(25), into: &report)

        report.findings.sort { $0.item.size == $1.item.size ? $0.item.id < $1.item.id : $0.item.size > $1.item.size }
        var seen = Set<String>()
        report.findings.removeAll { !seen.insert($0.item.url.standardizedFileURL.path).inserted }
        report.strayBuilds = FullCheckHistory.merge(report.strayBuilds)
        return report
    }

    /// Places with a fixed address that the walk does not reach, because they
    /// live in the Library or outside the home folder.
    private static func knownLocations(home: URL, options: Options, token: ScanCancellation, deadline: Date, into report: inout Report) {
        func children(_ relative: String) -> [URL] {
            let folder = home.appendingPathComponent(relative)
            var info = stat()
            guard lstat(folder.path, &info) == 0 else { return [] }
            do {
                return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
            } catch {
                report.unreadable.append(folder.path)
                return []
            }
        }
        func measure(_ url: URL) -> DiskItem? {
            guard !token.cancelled, Date() < deadline else { report.limited = true; return nil }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return nil }
            let mode = info.st_mode & mode_t(S_IFMT)
            guard mode == mode_t(S_IFDIR) || mode == mode_t(S_IFREG) else { return nil }
            let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec))
            let accessed = Date(timeIntervalSince1970: Double(info.st_atimespec.tv_sec))
            let identity = FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
            guard mode == mode_t(S_IFDIR) else {
                return DiskItem(url: url, size: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512, directory: false, symlink: false, modified: modified, accessed: accessed, identity: identity, incomplete: false)
            }
            let scan = DiskScanner.scan(url, cancellation: token, limit: 200_000, deadline: min(deadline, Date().addingTimeInterval(15)))
            return DiskItem(url: url, size: scan.logical, allocated: scan.allocated, directory: true, symlink: false, modified: modified, accessed: accessed, identity: identity, incomplete: scan.limited || scan.skipped > 0)
        }
        func add(_ item: DiskItem?, _ category: Category, _ reason: String, redundant: Bool, minimum: Int64 = 1_000_000) {
            guard let item, item.size >= minimum else { return }
            report.findings.append(Finding(item: item, category: category, reason: reason, redundant: redundant))
        }
        let day = DateFormatter()
        day.dateStyle = .medium; day.timeStyle = .none

        // Device backups. The name and date come from the backup's own record,
        // because a folder called 00008030-001A… tells a person nothing.
        for url in children("Library/Application Support/MobileSync/Backup").prefix(60) {
            var reason = String(localized: "Device backup made on this Mac")
            if let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist"), options: .mappedIfSafe),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                let name = plist["Device Name"] as? String ?? plist["Display Name"] as? String
                let date = plist["Last Backup Date"] as? Date
                switch (name, date) {
                case (let name?, let date?): reason = String(format: String(localized: "Backup of %@, last updated %@"), name, day.string(from: date))
                case (let name?, nil): reason = String(format: String(localized: "Backup of %@"), name)
                case (nil, let date?): reason = String(format: String(localized: "Device backup, last updated %@"), day.string(from: date))
                default: break
                }
            }
            add(measure(url), .deviceBackups, reason, redundant: false)
        }
        // Firmware fetched by Finder, the old iTunes, and Apple Configurator.
        let firmware = ["Library/iTunes/iPhone Software Updates", "Library/iTunes/iPad Software Updates", "Library/iTunes/iPod Software Updates",
                        "Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware"]
        for folder in firmware {
            for url in children(folder) where url.pathExtension.lowercased() == "ipsw" {
                add(measure(url), .deviceSoftware, String(localized: "Device firmware; downloaded again when a device needs it"), redundant: true)
            }
        }
        for dated in children("Library/Developer/Xcode/Archives").prefix(400) {
            for url in children("Library/Developer/Xcode/Archives/" + dated.lastPathComponent) where url.pathExtension == "xcarchive" {
                let item = measure(url)
                add(item, .xcodeArchives, String(format: String(localized: "Archive last changed %@ ago"), ago(idleDays(item?.modified, now: options.now))), redundant: false)
            }
        }
        for url in children("Library/Containers/com.apple.mail/Data/Library/Mail Downloads").prefix(500) {
            add(measure(url), .mailDownloads, String(localized: "Saved when the attachment was opened; the message still holds it"), redundant: true, minimum: 500_000)
        }
        let renderCaches = [
            ("Library/Application Support/Adobe/Common/Media Cache Files", "Adobe media cache"),
            ("Library/Application Support/Adobe/Common/Media Cache", "Adobe media cache index"),
            ("Library/Application Support/Adobe/Common/Peak Files", "Adobe audio peak files"),
            ("Movies/CacheClip", "DaVinci Resolve render cache"),
            ("Movies/Motion Templates.localized/.cache", "Motion template cache"),
            ("Library/Caches/com.apple.FinalCut", "Final Cut cache")
        ]
        for (relative, name) in renderCaches {
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            add(measure(url), .editingCaches, String(format: String(localized: "%@; the editor recreates it"), name), redundant: true, minimum: 10_000_000)
        }
        for url in children("Library/Logs").prefix(400) {
            let item = measure(url)
            add(item, .logs, String(format: String(localized: "Logs, last written %@ ago"), ago(idleDays(item?.modified, now: options.now))), redundant: true, minimum: 20_000_000)
        }
        for url in children("Library/Containers/com.utmapp.UTM/Data/Documents") where url.pathExtension.lowercased() == "utm" {
            let item = measure(url)
            add(item, .diskImages, String(format: String(localized: "Virtual machine, not opened for %@"), ago(idleDays(item?.lastTouched, now: options.now))), redundant: false, minimum: 50_000_000)
        }
        // The macOS installer is an application, but it is used once.
        for folder in options.applicationFolders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.hasPrefix("Install macOS") && name.hasSuffix(".app") {
                add(measure(folder.appendingPathComponent(name)), .installers, String(localized: "macOS installer; Software Update downloads it again"), redundant: true)
            }
        }
    }
}
