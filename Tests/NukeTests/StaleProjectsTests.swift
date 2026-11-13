import XCTest
@testable import Nuke

/// "Which of these am I done with?" is the question the Projects screen exists to
/// answer. The sweep must only name projects that are genuinely dormant.
final class StaleProjectsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func group(_ path: String, sizes: [Int64], ageDays: [Double?]) -> ProjectGroup {
        let entries = zip(sizes, ageDays).enumerated().map { index, pair in
            InventoryEntry(
                item: DiskItem(
                    url: URL(fileURLWithPath: path + "/artifact-\(index)"),
                    size: pair.0,
                    allocated: pair.0,
                    directory: true,
                    symlink: false,
                    modified: pair.1.map { now.addingTimeInterval(-$0 * 86_400) },
                    identity: nil,
                    incomplete: false
                ),
                category: "Build output",
                owner: "fixture",
                explanation: "fixture"
            )
        }
        return ProjectGroup(root: URL(fileURLWithPath: path), kind: "Rust", entries: entries)
    }

    func testNamesOnlyProjectsOlderThanTheCutoff() {
        let old = group("/tmp/fixture/dormant", sizes: [4_000_000_000], ageDays: [400])
        let recent = group("/tmp/fixture/current", sizes: [9_000_000_000], ageDays: [3])
        let sweep = StaleProjects.sweep([recent, old], months: 6, now: now)
        XCTAssertEqual(sweep.groups.map(\.id), [old.id])
        XCTAssertEqual(sweep.bytes, 4_000_000_000)
        XCTAssertEqual(sweep.count, 1)
    }

    /// The newest entry decides. One freshly rebuilt artifact means the project
    /// is alive, however old the rest of it looks.
    func testTheMostRecentEntryDecidesNotTheOldest() {
        let mixed = group("/tmp/fixture/mixed", sizes: [1_000_000_000, 500_000_000], ageDays: [400, 2])
        XCTAssertTrue(StaleProjects.sweep([mixed], months: 6, now: now).isEmpty)
    }

    /// Unknown is not old: a project with no dated entries must not be swept up.
    func testAProjectWithNoModificationDatesIsNotCalledStale() {
        let undated = group("/tmp/fixture/undated", sizes: [2_000_000_000], ageDays: [nil])
        XCTAssertTrue(StaleProjects.sweep([undated], months: 6, now: now).isEmpty)
    }

    /// Something running there is decisive regardless of file dates.
    func testAnActiveProjectIsExcludedEvenWhenItsFilesLookOld() {
        let old = group("/tmp/fixture/dormant", sizes: [4_000_000_000], ageDays: [400])
        let sweep = StaleProjects.sweep([old], months: 6, now: now, activeRoots: ["/tmp/fixture/dormant"])
        XCTAssertTrue(sweep.isEmpty)
    }

    func testEmptyProjectsAreNotWorthNaming() {
        let empty = group("/tmp/fixture/empty", sizes: [0], ageDays: [400])
        XCTAssertTrue(StaleProjects.sweep([empty], months: 6, now: now).isEmpty)
    }

    func testResultsAreLargestFirst() {
        let small = group("/tmp/fixture/small", sizes: [1_000_000], ageDays: [400])
        let large = group("/tmp/fixture/large", sizes: [8_000_000_000], ageDays: [400])
        let sweep = StaleProjects.sweep([small, large], months: 6, now: now)
        XCTAssertEqual(sweep.groups.map(\.id), [large.id, small.id])
    }

    func testTheCutoffIsConfigurable() {
        let aged = group("/tmp/fixture/aged", sizes: [1_000_000_000], ageDays: [100])
        XCTAssertTrue(StaleProjects.sweep([aged], months: 6, now: now).isEmpty)
        XCTAssertEqual(StaleProjects.sweep([aged], months: 2, now: now).count, 1)
    }
}
