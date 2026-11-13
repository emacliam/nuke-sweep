import XCTest
@testable import Nuke

/// The automatic cleanup is the only place the app acts without a person
/// confirming each item, so what it may take is pinned here from both sides:
/// what qualifies, and every reason something does not.
final class AutoCleanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ path: String, size: Int64 = 2_000_000_000, ageDays: Double?, incomplete: Bool = false, symlink: Bool = false) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), size: size, allocated: size, directory: true, symlink: symlink,
                 modified: ageDays.map { now.addingTimeInterval(-$0 * 86_400) }, identity: nil, incomplete: incomplete)
    }
    private func evidence(_ kind: CleanupEvidenceKind) -> CleanupEvidence {
        CleanupEvidence(kind: kind, detail: "Fixture evidence.", rebuild: "Rebuild from source.", gitIgnored: true)
    }
    private func signals(uncommitted: Set<String> = [], open openPaths: Set<String> = [], active: Set<String> = []) -> StorageTriage.Signals {
        var s = StorageTriage.Signals()
        s.uncommittedRoots = uncommitted; s.openPaths = openPaths; s.activeRoots = active; s.now = now
        return s
    }
    private func report(_ items: [DiskItem], kinds: [CleanupEvidenceKind], signals: StorageTriage.Signals? = nil) -> StorageTriage.Report {
        var evidenceByID: [String: CleanupEvidence] = [:]
        for (item, kind) in zip(items, kinds) { evidenceByID[item.id] = evidence(kind) }
        return StorageTriage.rank(items, evidence: evidenceByID, signals: signals ?? self.signals())
    }

    func testAStaleCacheWithNothingToWarnAboutIsEligible() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: 200)
        let found = AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 90, now: now)
        XCTAssertEqual(found.map(\.id), [cache.id])
    }

    func testSomethingTouchedInsideTheWindowIsLeftAlone() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: 60)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 90, now: now).isEmpty)
        XCTAssertFalse(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 30, now: now).isEmpty)
    }

    /// A read counts as use. A cache read on every build but never rewritten
    /// would otherwise look dormant and be cleared from under a working setup.
    func testARecentReadKeepsAnOldItemOutEvenWhenItWasNotWritten() {
        var cache = item("/tmp/fixture/Caches/gradle", ageDays: 400)
        cache.accessed = now.addingTimeInterval(-3 * 86_400)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 90, now: now).isEmpty)
    }

    func testAnItemWithNoDateIsNeverEligible() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: nil)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 30, now: now).isEmpty,
                      "Unknown age must not be read as old.")
    }

    func testAnythingWithoutPositiveEvidenceIsLeftForReview() {
        let ignored = item("/tmp/fixture/project/out", ageDays: 300)
        let unknown = item("/tmp/fixture/Stuff", ageDays: 300)
        let found = AutoClean.eligible(report([ignored, unknown], kinds: [.gitIgnored, .unknown]), idleDays: 90, now: now)
        XCTAssertTrue(found.isEmpty, "Git-ignored alone and unidentified storage are a person's call.")
    }

    func testBuildOutputBesideUncommittedWorkIsLeftForReview() {
        let build = item("/tmp/fixture/app/build", ageDays: 300)
        let found = AutoClean.eligible(
            report([build], kinds: [.buildOutput], signals: signals(uncommitted: ["/tmp/fixture/app"])),
            idleDays: 90, now: now
        )
        XCTAssertTrue(found.isEmpty, "A caution of any kind keeps an item out of the unattended set.")
    }

    /// On a Mac with no Time Machine every item carries a "no backup" caution.
    /// For something that rebuilds itself that is irrelevant, and treating it as
    /// a blocker would leave the automatic cleanup with nothing it may ever take.
    func testNoBackupDoesNotBlockSomethingThatRebuildsItself() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: 200)
        var s = signals(); s.backupCoverage = [cache.id: .excluded]
        let found = AutoClean.eligible(report([cache], kinds: [.knownCache], signals: s), idleDays: 90, now: now)
        XCTAssertEqual(found.map(\.id), [cache.id])
    }

    func testSomethingInUseIsLeftAlone() {
        let modules = item("/tmp/fixture/app/node_modules", ageDays: 300)
        let held = report([modules], kinds: [.dependency], signals: signals(open: ["/tmp/fixture/app/node_modules/.bin/tool"]))
        XCTAssertTrue(AutoClean.eligible(held, idleDays: 90, now: now).isEmpty)
        let serving = report([modules], kinds: [.dependency], signals: signals(active: ["/tmp/fixture/app"]))
        XCTAssertTrue(AutoClean.eligible(serving, idleDays: 90, now: now).isEmpty)
    }

    func testAnIncompleteMeasurementIsLeftAlone() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: 300, incomplete: true)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 90, now: now).isEmpty)
    }

    /// A hand-edited preference must not be able to shorten the wait below the
    /// shortest choice the app offers.
    func testTheWaitCannotBeLoweredBelowTheShortestChoice() {
        let cache = item("/tmp/fixture/Caches/pip", ageDays: 10)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: 0, now: now).isEmpty)
        XCTAssertTrue(AutoClean.eligible(report([cache], kinds: [.knownCache]), idleDays: -5, now: now).isEmpty)
    }

    func testItemsReviewPreparationFoundOpenInAnAppAreDropped() {
        let pip = item("/tmp/fixture/Caches/pip", ageDays: 300), npm = item("/tmp/fixture/Caches/npm", ageDays: 300)
        let kept = AutoClean.withoutWarned([pip, npm], warnings: ["pip is open in Terminal. Close those apps or builds before continuing."])
        XCTAssertEqual(kept.map(\.name), ["npm"])
        XCTAssertEqual(AutoClean.withoutWarned([pip, npm], warnings: []).count, 2)
    }

    func testItIsOffAndNinetyDaysUntilSomeoneChoosesOtherwise() {
        let defaults = UserDefaults.standard
        let savedEnabled = defaults.object(forKey: "nuke.autoClean.enabled"), savedDays = defaults.object(forKey: "nuke.autoClean.idleDays")
        defer {
            defaults.set(savedEnabled, forKey: "nuke.autoClean.enabled")
            defaults.set(savedDays, forKey: "nuke.autoClean.idleDays")
        }
        defaults.removeObject(forKey: "nuke.autoClean.enabled"); defaults.removeObject(forKey: "nuke.autoClean.idleDays")
        XCTAssertFalse(AutoClean.enabled)
        XCTAssertEqual(AutoClean.idleDays, 90)
        AutoClean.idleDays = 7
        XCTAssertEqual(AutoClean.idleDays, 90, "A value that is not one of the offered choices falls back to the default.")
        AutoClean.idleDays = 180
        XCTAssertEqual(AutoClean.idleDays, 180)
    }
}

/// "Something grew" is a status; naming what grew is the answer. These pin that
/// the names are right and that nothing is called growth that was not measured.
final class FullCheckGrowthTests: XCTestCase {
    private func item(_ path: String, size: Int64) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), size: size, allocated: size, directory: true,
                 symlink: false, modified: nil, identity: nil, incomplete: false)
    }
    private let gb: Int64 = 1_000_000_000

    func testTheLargestGrowthLeadsAndSmallChangesAreNotNamed() {
        let previous = ["/tmp/f/DerivedData": 2 * gb, "/tmp/f/pip": 1 * gb, "/tmp/f/npm": 1 * gb]
        let current = [item("/tmp/f/DerivedData", size: 10 * gb), item("/tmp/f/pip", size: 3 * gb), item("/tmp/f/npm", size: 1 * gb + 50_000_000)]
        let growers = FullCheckHistory.growers(previous: previous, current: current)
        XCTAssertEqual(growers.map(\.path), ["/tmp/f/DerivedData", "/tmp/f/pip"])
        XCTAssertEqual(growers.first?.delta, 8 * gb)
        XCTAssertEqual(growers.first?.isNew, false)
    }

    func testSomethingThatShrankIsNotGrowth() {
        let growers = FullCheckHistory.growers(previous: ["/tmp/f/pip": 5 * gb], current: [item("/tmp/f/pip", size: 1 * gb)])
        XCTAssertTrue(growers.isEmpty)
    }

    func testALocationAbsentFromASmallRecordIsNew() {
        let growers = FullCheckHistory.growers(previous: ["/tmp/f/pip": gb], current: [item("/tmp/f/pip", size: gb), item("/tmp/f/web/node_modules", size: 4 * gb)])
        XCTAssertEqual(growers.map(\.path), ["/tmp/f/web/node_modules"])
        XCTAssertEqual(growers.first?.isNew, true)
        XCTAssertEqual(growers.first?.name, "web/node_modules", "A bare folder name is not enough to recognise.")
    }

    /// A full record only kept the largest locations. Something missing from it
    /// may have existed below the cut-off, so only growth above that is claimed.
    func testALocationAbsentFromAFullRecordOnlyClaimsGrowthAboveTheCutOff() {
        var previous: [String: Int64] = [:]
        for index in 0..<FullCheckHistory.storedSizes { previous["/tmp/f/item-\(index)"] = 2 * gb }
        let growers = FullCheckHistory.growers(previous: previous, current: [item("/tmp/f/late", size: 5 * gb), item("/tmp/f/small", size: 2 * gb + 1)])
        XCTAssertEqual(growers.map(\.path), ["/tmp/f/late"])
        XCTAssertEqual(growers.first?.delta, 3 * gb)
        XCTAssertEqual(growers.first?.isNew, false, "It cannot be called new when it may have been there, just smaller.")
    }

    func testNothingIsCalledNewWhenTheTwoChecksLookedInDifferentPlaces() {
        let growers = FullCheckHistory.growers(previous: ["/tmp/f/pip": gb], current: [item("/tmp/f/web/node_modules", size: 4 * gb)], includeNew: false)
        XCTAssertTrue(growers.isEmpty)
    }

    func testAFirstCheckHasNothingToCompareWith() {
        XCTAssertTrue(FullCheckHistory.growers(previous: nil, current: [item("/tmp/f/pip", size: 9 * gb)]).isEmpty)
        XCTAssertNil(FullCheckHistory.growthSentence([], since: Date()))
    }

    func testTheStoredRecordIsBoundedAndKeepsTheLargest() {
        let items = (0..<(FullCheckHistory.storedSizes + 50)).map { item("/tmp/f/item-\($0)", size: Int64($0 + 1)) }
        let sizes = FullCheckHistory.sizes(of: items)
        XCTAssertEqual(sizes.count, FullCheckHistory.storedSizes)
        XCTAssertNil(sizes["/tmp/f/item-0"], "The smallest locations are the ones dropped.")
        XCTAssertNotNil(sizes["/tmp/f/item-\(FullCheckHistory.storedSizes + 49)"])
    }

    func testARecordSavedBeforeSizesExistedStillLoads() throws {
        let legacy = #"{"date":700000000,"regenerableBytes":5,"candidateBytes":9}"#
        let record = try JSONDecoder().decode(FullCheckRecord.self, from: Data(legacy.utf8))
        XCTAssertNil(record.sizes)
        XCTAssertNil(record.measuredProjects)
        XCTAssertEqual(record.regenerableBytes, 5)
    }

    func testTheSentenceNamesEachLocation() throws {
        let growers = [FullCheckGrower(path: "/tmp/f/Xcode/DerivedData", delta: 8 * gb, isNew: false),
                       FullCheckGrower(path: "/tmp/f/web/node_modules", delta: 4 * gb, isNew: true)]
        let sentence = try XCTUnwrap(FullCheckHistory.growthSentence(growers, since: Date(timeIntervalSince1970: 1_790_000_000)))
        XCTAssertTrue(sentence.contains("Xcode/DerivedData +"))
        XCTAssertTrue(sentence.contains("web/node_modules new at"))
    }
}

final class DiskAccessProbeTests: XCTestCase {
    private var home: URL!
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nuke-access-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        let protected = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: protected.path)
        try? FileManager.default.removeItem(at: home)
    }
    private func makeProbeFile(permissions: Int) throws {
        let directory = home.appendingPathComponent("Library/Application Support/com.apple.TCC")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("TCC.db")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
    }

    func testAReadableProtectedFileMeansAccessIsGranted() throws {
        try makeProbeFile(permissions: 0o600)
        XCTAssertEqual(DiskAccessProbe.status(home: home), .granted)
    }

    func testARefusedProtectedFileMeansAccessIsMissing() throws {
        try XCTSkipIf(getuid() == 0, "Root reads regardless of permissions.")
        try makeProbeFile(permissions: 0o000)
        XCTAssertEqual(DiskAccessProbe.status(home: home), .missing)
    }

    /// With nothing to probe the answer is "cannot tell", never a guess: saying
    /// access is missing would nag someone who has already granted it.
    func testNothingToProbeIsUnknownRatherThanMissing() {
        XCTAssertEqual(DiskAccessProbe.status(home: home), .unknown)
    }
}
