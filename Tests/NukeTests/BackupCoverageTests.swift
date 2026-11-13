import XCTest
@testable import Nuke

/// Backup coverage answers "if this turns out to be a mistake, can it come back?".
/// The failure that matters is reporting *unknown* as *backed up*, or an
/// unconfigured Mac as protected — both would make the app sound safer than it is.
final class BackupCoverageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BackupCoverageService.forgetCachedDestination()
    }
    override func tearDown() {
        BackupCoverageService.forgetCachedDestination()
        super.tearDown()
    }

    /// Verified against the real tool: `tmutil destinationinfo` exits 0 and prints
    /// "No destinations configured." when nothing is set up. Treating a non-zero
    /// status as the no-backup signal would have missed this entirely.
    private func runner(destination: CommandResult, excluded: CommandResult? = nil)
        -> (String, [String], TimeInterval) -> CommandResult {
        { _, arguments, _ in
            if arguments.first == "destinationinfo" { return destination }
            return excluded ?? CommandResult(output: "", status: 1)
        }
    }

    func testNoDestinationConfiguredIsReportedAsUnprotected() {
        let run = runner(destination: .init(output: "tmutil: No destinations configured.", status: 0))
        XCTAssertEqual(BackupCoverageService.hasDestination(run: run), false)
        let coverage = BackupCoverageService.coverage(for: URL(fileURLWithPath: "/tmp/x"), run: run)
        XCTAssertEqual(coverage, .noBackupConfigured)
        XCTAssertTrue(coverage.isUnprotected)
    }

    func testAnExcludedPathIsRecognised() {
        let run = runner(
            destination: .init(output: "Name: Backup\nDestination ID: ABC-123", status: 0),
            excluded: .init(output: "[Excluded]  /Users/someone/Library/Caches", status: 0)
        )
        let coverage = BackupCoverageService.coverage(for: URL(fileURLWithPath: "/Users/someone/Library/Caches"), run: run)
        XCTAssertEqual(coverage, .excluded)
        XCTAssertTrue(coverage.isUnprotected)
    }

    func testAnIncludedPathIsRecognisedAndNotCalledUnprotected() {
        let run = runner(
            destination: .init(output: "Name: Backup\nDestination ID: ABC-123", status: 0),
            excluded: .init(output: "[Included]  /Users/someone/Documents", status: 0)
        )
        let coverage = BackupCoverageService.coverage(for: URL(fileURLWithPath: "/Users/someone/Documents"), run: run)
        XCTAssertEqual(coverage, .included)
        XCTAssertFalse(coverage.isUnprotected)
    }

    /// The central honesty rule: a question that could not be answered is never
    /// reported as a missing backup, and never as a present one.
    func testAFailedProbeIsUnknownRatherThanUnprotected() {
        let failing = runner(destination: .init(output: "", status: 127))
        XCTAssertNil(BackupCoverageService.hasDestination(run: failing))
        let coverage = BackupCoverageService.coverage(for: URL(fileURLWithPath: "/tmp/x"), run: failing)
        XCTAssertEqual(coverage, .unknown)
        XCTAssertFalse(coverage.isUnprotected, "Unknown must not be treated as unprotected.")
    }

    func testUnrecognisedDestinationOutputIsUnknownNotAbsent() {
        let odd = runner(destination: .init(output: "something nobody expected", status: 0))
        XCTAssertNil(BackupCoverageService.hasDestination(run: odd),
                     "Unparseable output is unknown, not proof that no backup exists.")
    }

    func testAnExclusionProbeThatFailsIsUnknown() {
        let run = runner(
            destination: .init(output: "Destination ID: ABC-123", status: 0),
            excluded: .init(output: "tmutil: unable to read", status: 1)
        )
        XCTAssertEqual(BackupCoverageService.coverage(for: URL(fileURLWithPath: "/tmp/x"), run: run), .unknown)
    }

    func testEveryStateExplainsItselfWithoutClaimingSafety() throws {
        for state in [BackupCoverage.included, .excluded, .noBackupConfigured, .unknown] {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
            XCTAssertNoThrow(try AIOutputLimits.advice(state.detail), "\(state) copy must not claim safety")
        }
    }

    /// `included` is scope, not a guarantee that a backup actually ran.
    func testIncludedCopyDoesNotPromiseABackupExists() {
        XCTAssertTrue(BackupCoverage.included.detail.contains("may hold"))
        XCTAssertTrue(BackupCoverage.included.detail.lowercased().contains("verify"))
    }
}
