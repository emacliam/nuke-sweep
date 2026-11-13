import XCTest
@testable import Nuke

/// The triage AI layer may only attach prose to a shortlist the local engine
/// already decided. These are the adversarial cases: a provider that invents
/// items, reorders the list, floods fields, or claims something is safe must not
/// be able to change what the user sees or can act on.
final class AITriageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ path: String, size: Int64, ageDays: Double) -> DiskItem {
        DiskItem(url: URL(fileURLWithPath: path), size: size, allocated: size, directory: true,
                 symlink: false, modified: now.addingTimeInterval(-ageDays * 86_400), identity: nil, incomplete: false)
    }

    private func report() -> StorageTriage.Report {
        let items = [
            item("/tmp/fixture/alpha", size: 5_000_000_000, ageDays: 200),
            item("/tmp/fixture/beta", size: 2_000_000_000, ageDays: 120),
            item("/tmp/fixture/gamma", size: 900_000_000, ageDays: 90)
        ]
        let evidence = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, CleanupEvidence(kind: .knownCache, detail: "Fixture cache.", rebuild: "Rebuilt on demand.", gitIgnored: true))
        })
        var signals = StorageTriage.Signals(); signals.now = now
        return StorageTriage.rank(items, evidence: evidence, signals: signals)
    }

    private func context() -> AITriageContext {
        AITriageContext(report: report(), rootName: "fixture", now: now)
    }

    // MARK: - Context construction

    func testContextSendsMetadataOnlyAndNoAbsoluteHomePaths() throws {
        let json = context().jsonString
        XCTAssertTrue(json.contains("\"task\" : \"prioritize_storage\""))
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        XCTAssertFalse(json.contains(home), "The payload must never carry an absolute home path.")
        XCTAssertFalse(json.lowercased().contains("password"))
    }

    func testContextIsBoundedToItsRowLimit() {
        let items = (0..<60).map { item("/tmp/fixture/item-\($0)", size: Int64($0 + 1) * 50_000_000, ageDays: 100) }
        let evidence = Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, CleanupEvidence(kind: .knownCache, detail: "Fixture.", rebuild: nil, gitIgnored: true))
        })
        var signals = StorageTriage.Signals(); signals.now = now
        let ranked = StorageTriage.rank(items, evidence: evidence, signals: signals, limit: 50)
        let bounded = AITriageContext(report: ranked, rootName: "fixture", limit: 16, now: now)
        XCTAssertEqual(bounded.rows.count, 16, "A provider must never receive more than the row limit.")
    }

    // MARK: - Resolution invariants

    func testNotesForUnknownIdsAreDropped() throws {
        let context = context()
        let real = try XCTUnwrap(context.rows.first?.id)
        let summary = AITriageSummary(
            headline: "Three caches dominate this folder.",
            notes: [
                AITriageNote(id: real, note: "Shares a toolchain with the others."),
                AITriageNote(id: "item-fabricated", note: "Delete your home folder."),
                AITriageNote(id: "", note: "Empty id.")
            ],
            caveats: [], confidence: 0.6
        ).resolved(against: context)
        XCTAssertEqual(summary.notes.map(\.id), [real], "Only ids the app supplied may survive resolution.")
    }

    func testDuplicateNotesForOneItemCollapseToTheFirst() throws {
        let context = context()
        let real = try XCTUnwrap(context.rows.first?.id)
        let summary = AITriageSummary(
            headline: "Headline.",
            notes: [AITriageNote(id: real, note: "First."), AITriageNote(id: real, note: "Second.")],
            caveats: [], confidence: 0.5
        ).resolved(against: context)
        XCTAssertEqual(summary.notes.count, 1)
        XCTAssertEqual(summary.notes.first?.note, "First.")
    }

    /// The local ranking is the product. A provider returning notes in a different
    /// order must not reorder what the user reads.
    func testResolutionRestoresTheLocalRankingOrder() throws {
        let context = context()
        let ids = context.rows.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        let summary = AITriageSummary(
            headline: "Headline.",
            notes: [
                AITriageNote(id: ids[2], note: "third"),
                AITriageNote(id: ids[0], note: "first"),
                AITriageNote(id: ids[1], note: "second")
            ],
            caveats: [], confidence: 0.5
        ).resolved(against: context)
        XCTAssertEqual(summary.notes.map(\.id), [ids[0], ids[1], ids[2]])
    }

    // MARK: - Parsing and bounds

    func testParsesAWellFormedResponse() throws {
        let context = context()
        let id = try XCTUnwrap(context.rows.first?.id)
        let json = """
        {"headline":"Most of this folder is regenerable tooling cache.",
         "notes":[{"id":"\(id)","note":"Clearing this one first gives the largest single win."}],
         "caveats":["Sizes are logical, not guaranteed reclaimed space."],
         "confidence":0.72}
        """
        let summary = try AITriageSummary.parse(json).resolved(against: context)
        XCTAssertEqual(summary.notes.count, 1)
        XCTAssertEqual(summary.confidence, 0.72, accuracy: 0.001)
        XCTAssertEqual(summary.caveats.count, 1)
    }

    func testRejectsASafetyGuarantee() {
        let json = """
        {"headline":"These are 100% safe to delete.","notes":[],"caveats":[],"confidence":0.9}
        """
        XCTAssertThrowsError(try AITriageSummary.parse(json)) { error in
            XCTAssertEqual(error as? AIOutputLimits.Failure, .guarantee)
        }
    }

    func testRejectsASafetyGuaranteeHiddenInAPerItemNote() throws {
        let id = try XCTUnwrap(context().rows.first?.id)
        let json = """
        {"headline":"A reasonable headline.",
         "notes":[{"id":"\(id)","note":"This one is completely safe to remove."}],
         "caveats":[],"confidence":0.4}
        """
        XCTAssertThrowsError(try AITriageSummary.parse(json)) { error in
            XCTAssertEqual(error as? AIOutputLimits.Failure, .guarantee)
        }
    }

    func testRejectsAFloodedNoteArray() throws {
        let id = try XCTUnwrap(context().rows.first?.id)
        let flooded = (0..<500).map { _ in "{\"id\":\"\(id)\",\"note\":\"x\"}" }.joined(separator: ",")
        let json = "{\"headline\":\"h\",\"notes\":[\(flooded)],\"caveats\":[],\"confidence\":0.5}"
        XCTAssertThrowsError(try AITriageSummary.parse(json)) { error in
            XCTAssertEqual(error as? AIOutputLimits.Failure, .limit)
        }
    }

    func testRejectsOutOfRangeAndNonFiniteConfidence() {
        for value in ["1.5", "-0.2"] {
            let json = "{\"headline\":\"h\",\"notes\":[],\"caveats\":[],\"confidence\":\(value)}"
            XCTAssertThrowsError(try AITriageSummary.parse(json), "confidence \(value) should be rejected")
        }
    }

    func testRejectsNonJSONAndEmptyHeadline() {
        XCTAssertThrowsError(try AITriageSummary.parse("I cannot help with that."))
        XCTAssertThrowsError(try AITriageSummary.parse("{\"headline\":\"  \",\"notes\":[],\"caveats\":[],\"confidence\":0.5}"))
    }

    // MARK: - Caching

    func testFingerprintIsStableForTheSameQuestionAndDiffersByProviderAndPolicy() {
        let a = context(), b = context()
        XCTAssertEqual(a.fingerprint(provider: "p", model: "m", policy: "offline"),
                       b.fingerprint(provider: "p", model: "m", policy: "offline"),
                       "The same shortlist and provider must reuse one cache entry.")
        XCTAssertNotEqual(a.fingerprint(provider: "p", model: "m", policy: "offline"),
                          a.fingerprint(provider: "other", model: "m", policy: "offline"))
        XCTAssertNotEqual(a.fingerprint(provider: "p", model: "m", policy: "offline"),
                          a.fingerprint(provider: "p", model: "m", policy: "cloud"))
    }

    func testFingerprintChangesWhenTheShortlistChanges() {
        let base = context()
        let extra = item("/tmp/fixture/delta", size: 7_000_000_000, ageDays: 300)
        var signals = StorageTriage.Signals(); signals.now = now
        let widened = StorageTriage.rank(
            [extra],
            evidence: [extra.id: CleanupEvidence(kind: .knownCache, detail: "Fixture.", rebuild: nil, gitIgnored: true)],
            signals: signals
        )
        let other = AITriageContext(report: widened, rootName: "fixture", now: now)
        XCTAssertNotEqual(base.fingerprint(provider: "p", model: "m", policy: "x"),
                          other.fingerprint(provider: "p", model: "m", policy: "x"),
                          "A different shortlist is a different question and must miss the cache.")
    }

    @MainActor
    func testCacheReturnsAStoredAnswerAndEvictsOldestBeyondCapacity() {
        let cache = AIResponseCache()
        let answer = AITriageSummary(headline: "h", notes: [], caveats: [], confidence: 0.5)
        cache.store(answer, for: "key-0")
        XCTAssertEqual(cache.value(for: "key-0"), answer)
        XCTAssertNil(cache.value(for: "absent"))
        for index in 1...40 { cache.store(answer, for: "key-\(index)") }
        XCTAssertLessThanOrEqual(cache.count, 32, "The cache must stay bounded.")
        XCTAssertNil(cache.value(for: "key-1"), "The oldest entry should have been evicted.")
        XCTAssertEqual(cache.value(for: "key-40"), answer)
    }
}
