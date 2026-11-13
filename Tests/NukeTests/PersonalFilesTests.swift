import XCTest
import Darwin
@testable import Nuke

/// Personal files never rebuild themselves, so these rules are pinned from
/// both sides: what is listed and why, and what must never be listed at all.
final class PersonalFilesRuleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func facts(_ name: String, size: Int64 = 20_000_000, idle: Double? = 200, written: Double? = nil) -> PersonalFiles.Facts {
        var facts = PersonalFiles.Facts(name: name, size: size)
        facts.now = now
        facts.touched = idle.map { now.addingTimeInterval(-$0 * 86_400) }
        facts.modified = (written ?? idle).map { now.addingTimeInterval(-$0 * 86_400) }
        return facts
    }

    func testAnInstallerForAnInstalledAppIsCalledSurplus() {
        var f = facts("Slack-4.36.140-macOS.dmg", idle: 2)
        f.installed = ["slack": "Slack"]
        let verdict = PersonalFiles.judge(f)
        XCTAssertEqual(verdict?.category, .installers)
        XCTAssertEqual(verdict?.redundant, true)
        XCTAssertTrue(verdict?.reason.contains("Slack") == true)
    }

    func testARecentInstallerWithNoInstalledAppIsListedButNotCalledSurplus() {
        let verdict = PersonalFiles.judge(facts("Mystery.dmg", idle: 2))
        XCTAssertEqual(verdict?.category, .installers)
        XCTAssertEqual(verdict?.redundant, false)
    }

    func testInstalledAppMatching() {
        let installed = ["googlechrome": "Google Chrome", "slack": "Slack", "visualstudiocode": "Visual Studio Code", "xcode": "Xcode", "1password": "1Password", "go": "Go"]
        XCTAssertEqual(PersonalFiles.installedApp(for: "googlechrome.dmg", installed: installed), "Google Chrome")
        XCTAssertEqual(PersonalFiles.installedApp(for: "Google Chrome 121.0.dmg", installed: installed), "Google Chrome")
        XCTAssertEqual(PersonalFiles.installedApp(for: "Slack-4.36.140-macOS.dmg", installed: installed), "Slack")
        XCTAssertEqual(PersonalFiles.installedApp(for: "Xcode_15.2.xip", installed: installed), "Xcode")
        XCTAssertEqual(PersonalFiles.installedApp(for: "1Password-8.10.pkg", installed: installed), "1Password")
        XCTAssertEqual(PersonalFiles.installedApp(for: "Visual Studio Code - Insiders.dmg", installed: installed), "Visual Studio Code")
        // Too short to mean anything, and a name that only starts the same.
        XCTAssertNil(PersonalFiles.installedApp(for: "go.pkg", installed: installed))
        XCTAssertNil(PersonalFiles.installedApp(for: "Slackware-15.dmg", installed: installed))
        XCTAssertNil(PersonalFiles.installedApp(for: "12345.dmg", installed: installed))
    }

    func testCopyNamesPointAtTheirOriginal() {
        XCTAssertEqual(PersonalFiles.originalName(ofCopy: "report (2).pdf"), "report.pdf")
        XCTAssertEqual(PersonalFiles.originalName(ofCopy: "report copy.pdf"), "report.pdf")
        XCTAssertEqual(PersonalFiles.originalName(ofCopy: "report copy 3.pdf"), "report.pdf")
        XCTAssertEqual(PersonalFiles.originalName(ofCopy: "report 2.pdf"), "report.pdf")
        XCTAssertEqual(PersonalFiles.originalName(ofCopy: "archive (1)"), "archive")
        XCTAssertNil(PersonalFiles.originalName(ofCopy: "report.pdf"))
        XCTAssertNil(PersonalFiles.originalName(ofCopy: "photocopy.pdf"))
        XCTAssertNil(PersonalFiles.originalName(ofCopy: "IMG 2024.jpg"))
        XCTAssertNil(PersonalFiles.originalName(ofCopy: "(2).pdf"))
    }

    func testACopyNeedsASiblingOfTheSameSizeAndIsOnlyASuggestion() {
        var f = facts("report (1).pdf", size: 4_000_000, idle: 5)
        f.siblingFiles = ["report.pdf": 4_000_000]
        let verdict = PersonalFiles.judge(f)
        XCTAssertEqual(verdict?.category, .repeatDownloads)
        XCTAssertEqual(verdict?.compareWith, "report.pdf")
        f.siblingFiles = ["report.pdf": 4_000_001]
        XCTAssertNil(PersonalFiles.judge(f))
        f.siblingFiles = [:]
        XCTAssertNil(PersonalFiles.judge(f))
    }

    func testAnArchiveIsListedOnlyWhenItsFolderSitsBesideIt() {
        var f = facts("site.tar.gz", idle: 5)
        XCTAssertNil(PersonalFiles.judge(f))
        f.siblingFolders = ["site"]
        XCTAssertEqual(PersonalFiles.judge(f)?.category, .extractedArchives)
        XCTAssertEqual(PersonalFiles.unpackedName(ofArchive: "photos.zip"), "photos")
    }

    func testADownloadStillBeingWrittenIsNeverListed() {
        XCTAssertNil(PersonalFiles.judge(facts("movie.mp4.crdownload", size: 900_000_000, idle: 0, written: 0)))
        XCTAssertNil(PersonalFiles.judge(facts("movie.mp4.part", size: 900_000_000, idle: 2, written: 2)))
        let stale = PersonalFiles.judge(facts("movie.mp4.crdownload", size: 900_000_000, idle: 0, written: 9))
        XCTAssertEqual(stale?.category, .partialDownloads)
    }

    func testRecordingsScreenshotsAndVideoAreToldApart() {
        XCTAssertEqual(PersonalFiles.judge(facts("Screen Recording 2025-03-01 at 10.00.00.mov"))?.category, .screenRecordings)
        XCTAssertEqual(PersonalFiles.judge(facts("zoom_0.mp4"))?.category, .screenRecordings)
        var meeting = facts("standup.mp4"); meeting.parent = "zoom"
        XCTAssertEqual(PersonalFiles.judge(meeting)?.category, .screenRecordings)
        XCTAssertEqual(PersonalFiles.judge(facts("holiday.mov", size: 80_000_000))?.category, .video)
        XCTAssertNil(PersonalFiles.judge(facts("clip.mov", size: 20_000_000, idle: 20)))
        XCTAssertEqual(PersonalFiles.judge(facts("Screenshot 2025-01-01 at 09.00.00.png", size: 300_000))?.category, .screenshots)
        // A screenshot from last week is still in use; a holiday photo is never listed.
        XCTAssertNil(PersonalFiles.judge(facts("Screenshot 2025-01-01 at 09.00.00.png", size: 300_000, idle: 6)))
        XCTAssertNil(PersonalFiles.judge(facts("IMG_0042.png", size: 9_000_000, idle: 900)))
    }

    func testAgeAloneOnlyCountsInDownloadsOrForVeryLargeFiles() {
        var document = facts("thesis.pdf", size: 30_000_000, idle: 400)
        XCTAssertNil(PersonalFiles.judge(document))
        document.inDownloads = true
        XCTAssertEqual(PersonalFiles.judge(document)?.category, .oldDownloads)
        XCTAssertEqual(PersonalFiles.judge(document)?.redundant, false)
        document.touched = now.addingTimeInterval(-10 * 86_400)
        XCTAssertNil(PersonalFiles.judge(document))
        XCTAssertEqual(PersonalFiles.judge(facts("dataset.bin", size: 2_000_000_000, idle: 300))?.category, .largeForgotten)
        XCTAssertNil(PersonalFiles.judge(facts("dataset.bin", size: 2_000_000_000, idle: 100)))
        // No usable date is never read as "old".
        XCTAssertNil(PersonalFiles.judge(facts("dataset.bin", size: 2_000_000_000, idle: nil)))
    }

    func testOtherKindsAreRecognised() {
        XCTAssertEqual(PersonalFiles.judge(facts("iPhone15,2_17.2_Restore.ipsw", size: 7_000_000_000, idle: 1))?.category, .deviceSoftware)
        XCTAssertEqual(PersonalFiles.judge(facts("ubuntu-24.04.iso", size: 5_000_000_000, idle: 1))?.category, .diskImages)
        XCTAssertEqual(PersonalFiles.judge(facts("interview.wav", size: 600_000_000, idle: 1))?.category, .audio)
        XCTAssertEqual(PersonalFiles.judge(facts("setup.exe", idle: 40))?.category, .installers)
        // A phone app package may be someone's own release build.
        let bundle = PersonalFiles.judge(facts("shop-release.aab", idle: 400))
        XCTAssertEqual(bundle?.category, .appPackages)
        XCTAssertEqual(bundle?.redundant, false)
    }

    func testEveryCategoryExplainsItselfAndOnlyRedundantKindsClaimARecoveryPath() {
        for category in PersonalFiles.Category.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.explanation.isEmpty)
        }
        for category in [PersonalFiles.Category.video, .screenRecordings, .screenshots, .deviceBackups, .diskImages, .oldDownloads, .largeForgotten, .xcodeArchives, .audio, .appPackages] {
            XCTAssertEqual(category.recovery, .onlyCopy, "\(category) cannot be recreated and must say so")
        }
    }
}

/// The search itself, against a home folder built for the test.
final class PersonalFilesScanTests: XCTestCase {
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/personal-" + UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: home) }

    @discardableResult
    private func file(_ relative: String, bytes count: Int = 200_000, fill: UInt8 = 7, ageDays: Double = 0) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: count).write(to: url)
        try age(url, days: ageDays)
        return url
    }
    private func folder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    /// Sets both the read and the write time, since either counts as use.
    private func age(_ url: URL, days: Double) throws {
        let then = Date().addingTimeInterval(-days * 86_400).timeIntervalSince1970
        var times = [timeval(tv_sec: Int(then), tv_usec: 0), timeval(tv_sec: Int(then), tv_usec: 0)]
        XCTAssertEqual(utimes(url.path, &times), 0)
    }
    private func scan(excluding: [URL] = []) -> PersonalFiles.Report {
        var options = PersonalFiles.Options()
        options.home = home
        options.applicationFolders = [home.appendingPathComponent("Applications")]
        options.excluded = excluding
        options.budget = 30
        return PersonalFiles.scan(options)
    }
    private func category(_ report: PersonalFiles.Report, _ name: String) -> PersonalFiles.Category? {
        report.findings.first { $0.item.name == name }?.category
    }

    func testFindsEachKindOfSurplusFileInARealisticHome() throws {
        _ = try folder("Applications/Slack.app")
        try file("Downloads/Slack-4.36.140-macOS.dmg", bytes: 1_200_000)
        try file("Downloads/report.pdf", bytes: 300_000, fill: 1)
        try file("Downloads/report (1).pdf", bytes: 300_000, fill: 1)
        try file("Downloads/notes.pdf", bytes: 300_000, fill: 1)
        try file("Downloads/notes (1).pdf", bytes: 300_000, fill: 2)
        try file("Downloads/site.zip", bytes: 1_500_000)
        _ = try folder("Downloads/site")
        try file("Downloads/film.mkv.crdownload", bytes: 400_000, ageDays: 10)
        try file("Downloads/old-manual.pdf", bytes: 6_000_000, ageDays: 200)
        try file("Downloads/fresh-manual.pdf", bytes: 6_000_000)
        try file("Desktop/Screenshot 2024-01-01 at 09.00.00.png", bytes: 50_000, ageDays: 90)
        try file("Desktop/Screen Recording 2024-01-01 at 09.00.00.mov", bytes: 5_500_000, ageDays: 90)
        try file("Movies/holiday.mp4", bytes: 51_000_000, ageDays: 40)
        try file("Documents/letter.docx", bytes: 400_000, ageDays: 900)

        let report = scan()
        XCTAssertEqual(category(report, "Slack-4.36.140-macOS.dmg"), .installers)
        XCTAssertEqual(report.findings.first { $0.item.name == "Slack-4.36.140-macOS.dmg" }?.redundant, true)
        XCTAssertEqual(category(report, "report (1).pdf"), .repeatDownloads)
        XCTAssertNil(category(report, "report.pdf"), "the original of a copy is never listed")
        XCTAssertNil(category(report, "notes (1).pdf"), "same name and size but different contents is not a copy")
        XCTAssertEqual(category(report, "site.zip"), .extractedArchives)
        XCTAssertEqual(category(report, "film.mkv.crdownload"), .partialDownloads)
        XCTAssertEqual(category(report, "old-manual.pdf"), .oldDownloads)
        XCTAssertNil(category(report, "fresh-manual.pdf"))
        XCTAssertEqual(category(report, "Screenshot 2024-01-01 at 09.00.00.png"), .screenshots)
        XCTAssertEqual(category(report, "Screen Recording 2024-01-01 at 09.00.00.mov"), .screenRecordings)
        XCTAssertEqual(category(report, "holiday.mp4"), .video)
        XCTAssertNil(category(report, "letter.docx"), "an old document is not clutter")
        XCTAssertEqual(Set(report.findings.map(\.id)).count, report.findings.count, "each file is listed once")
        XCTAssertEqual(report.totalBytes, report.findings.reduce(0) { $0 + $1.item.size })
        XCTAssertFalse(report.limited)
    }

    func testLibrariesSyncedFoldersHiddenFoldersAndAppsAreNotSearched() throws {
        try file("Pictures/Photos Library.photoslibrary/originals/clip.mov", bytes: 51_000_000)
        try file("Dropbox/shared.mov", bytes: 51_000_000)
        try file("Library/Mail/V10/attachment.mov", bytes: 51_000_000)
        try file(".Trash/gone.mov", bytes: 51_000_000)
        try file("Applications/Editor.app/Contents/Resources/intro.mov", bytes: 51_000_000)
        try file("Movies/Project.logicx/Media/take.wav", bytes: 101_000_000)

        let report = scan()
        XCTAssertTrue(report.findings.isEmpty, "found: \(report.findings.map(\.item.url.path))")
        XCTAssertEqual(report.syncFolders, ["Dropbox"])
    }

    func testAProjectIsNotSearchedForPersonalFilesButItsBuildFoldersAreMeasured() throws {
        try file("Desktop/side-project/package.json", bytes: 200)
        try file("Desktop/side-project/assets/demo.mp4", bytes: 51_000_000, ageDays: 400)
        try file("Desktop/side-project/node_modules/lib/index.js", bytes: 300_000)
        // A marker file loose in Documents must not turn Documents into a project.
        try file("Documents/requirements.txt", bytes: 200)
        try file("Documents/talk.mp4", bytes: 51_000_000, ageDays: 40)

        let report = scan()
        XCTAssertNil(category(report, "demo.mp4"))
        XCTAssertEqual(category(report, "talk.mp4"), .video)
        XCTAssertEqual(report.strayBuilds.map(\.name), ["node_modules"])
        XCTAssertEqual(report.strayProjectRoots.map { URL(fileURLWithPath: $0).lastPathComponent }, ["side-project"])
    }

    func testTheChosenCodeFolderIsLeftToItsOwnScan() throws {
        try file("Code/app/package.json", bytes: 200)
        try file("Code/app/node_modules/lib/index.js", bytes: 300_000)
        try file("Code/talk.mp4", bytes: 51_000_000, ageDays: 40)
        let report = scan(excluding: [home.appendingPathComponent("Code")])
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertTrue(report.strayBuilds.isEmpty)
    }

    func testAnOldFolderInDownloadsIsOfferedWholeAndAFreshOneIsSearched() throws {
        try file("Downloads/old-course/lesson.mp4", bytes: 6_000_000, ageDays: 300)
        try age(home.appendingPathComponent("Downloads/old-course"), days: 300)
        try file("Downloads/new-course/lesson.mp4", bytes: 51_000_000, ageDays: 2)
        let report = scan()
        XCTAssertEqual(category(report, "old-course"), .oldDownloads)
        XCTAssertNil(report.findings.first { $0.item.url.path.contains("old-course/") })
        XCTAssertEqual(report.findings.first { $0.item.url.path.hasSuffix("new-course/lesson.mp4") }?.category, .video)
    }

    func testKnownLibraryLocationsAreCovered() throws {
        try file("Library/Application Support/MobileSync/Backup/00008030-ABC/Manifest.db", bytes: 1_500_000)
        let info: [String: Any] = ["Device Name": "Test Phone", "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000)]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: home.appendingPathComponent("Library/Application Support/MobileSync/Backup/00008030-ABC/Info.plist"))
        try file("Library/iTunes/iPhone Software Updates/iPhone_17.ipsw", bytes: 1_500_000)
        try file("Library/Developer/Xcode/Archives/2024-01-01/App.xcarchive/Info.plist", bytes: 1_200_000)
        try file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/A1/invoice.pdf", bytes: 600_000)
        try file("Library/Logs/Chatty/app.log", bytes: 21_000_000)
        try file("Library/Logs/Quiet/app.log", bytes: 2_000)
        try file("Movies/Film.fcpbundle/Event/Render Files/High Quality Media/a.mov", bytes: 11_000_000)
        try file("Movies/Film.fcpbundle/Event/Original Media/a.mov", bytes: 51_000_000)
        try file("Applications/Install macOS Test.app/Contents/SharedSupport/InstallESD.dmg", bytes: 1_500_000)

        let report = scan()
        let backup = try XCTUnwrap(report.findings.first { $0.category == .deviceBackups })
        XCTAssertTrue(backup.reason.contains("Test Phone"))
        XCTAssertEqual(category(report, "iPhone_17.ipsw"), .deviceSoftware)
        XCTAssertEqual(category(report, "App.xcarchive"), .xcodeArchives)
        XCTAssertEqual(category(report, "A1"), .mailDownloads)
        XCTAssertEqual(category(report, "Chatty"), .logs)
        XCTAssertNil(category(report, "Quiet"))
        XCTAssertEqual(category(report, "Render Files"), .editingCaches)
        XCTAssertNil(report.findings.first { $0.item.url.path.contains("Original Media") }, "original footage is never offered")
        XCTAssertEqual(category(report, "Install macOS Test.app"), .installers)
    }

    func testAFindingPassesTheSameReviewAsEverythingElse() throws {
        let url = try file("Downloads/old-manual.pdf", bytes: 6_000_000, ageDays: 200)
        let report = scan()
        let item = try XCTUnwrap(report.findings.first { $0.item.url.lastPathComponent == url.lastPathComponent }?.item)
        let scope = CleanupScope(root: home, identity: try XCTUnwrap(FileIdentity.read(home)))
        let plan = ReviewPlanner.prepare([item], scopes: [scope], openFiles: { [] })
        XCTAssertEqual(plan.items.map(\.id), [item.id], "blocked: \(plan.failures)")
    }

    func testRemovingMovedPathsShrinksTheReport() throws {
        try file("Downloads/old-manual.pdf", bytes: 6_000_000, ageDays: 200)
        var report = scan()
        let path = try XCTUnwrap(report.findings.first?.item.url.path)
        report.remove(paths: [path])
        XCTAssertTrue(report.findings.isEmpty)
    }
}

/// Build folders found outside the code folder rank like any other, but an
/// unattended cleanup must leave them for a person.
final class StrayBuildTriageTests: XCTestCase {
    func testAStrayProjectsBuildFolderIsRankedButNeverCleanedUnattended() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = DiskItem(url: URL(fileURLWithPath: "/tmp/fixture/Desktop/side/node_modules"), size: 2_000_000_000, allocated: 2_000_000_000,
                            directory: true, symlink: false, modified: now.addingTimeInterval(-300 * 86_400), identity: nil, incomplete: false)
        let evidence = [item.id: CleanupEvidence(kind: .dependency, detail: "Fixture.", rebuild: "npm install", gitIgnored: true)]
        var signals = StorageTriage.Signals(); signals.now = now
        XCTAssertEqual(AutoClean.eligible(StorageTriage.rank([item], evidence: evidence, signals: signals), idleDays: 90, now: now).count, 1)
        signals.manualOnlyRoots = ["/tmp/fixture/Desktop/side"]
        let report = StorageTriage.rank([item], evidence: evidence, signals: signals)
        XCTAssertEqual(report.regenerable.count, 1, "still offered for review")
        XCTAssertTrue(AutoClean.eligible(report, idleDays: 90, now: now).isEmpty)
    }
}
