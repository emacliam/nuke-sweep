import XCTest
@testable import Nuke

/// The largest folders on a developer's Mac live outside DerivedData. When the
/// catalogue does not describe them, every one reports "no evidence", which reads
/// as a warning about storage whose purpose is in fact well understood.
final class DeveloperEvidenceTests: XCTestCase {
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path }
    private func classify(_ relative: String) -> CleanupEvidence {
        CleanupEvidenceService.classify(URL(fileURLWithPath: home + "/" + relative))
    }

    func testXcodeDeviceSupportIsEvidencedAsARegenerableCache() {
        for platform in ["iOS", "watchOS", "tvOS", "macOS"] {
            let evidence = classify("Library/Developer/Xcode/\(platform) DeviceSupport")
            XCTAssertEqual(evidence.kind, .knownCache, "\(platform) DeviceSupport should be recognised.")
            XCTAssertNotNil(evidence.rebuild, "A cache claim must say how it comes back.")
        }
    }

    func testDeviceSupportChildrenInheritTheEvidence() {
        let evidence = classify("Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)/Symbols")
        XCTAssertEqual(evidence.kind, .knownCache)
    }

    func testDocumentationAndSimulatorCachesAreRecognised() {
        XCTAssertEqual(classify("Library/Developer/Xcode/DocumentationCache").kind, .knownCache)
        XCTAssertEqual(classify("Library/Developer/Xcode/DocumentationIndex").kind, .knownCache)
        XCTAssertEqual(classify("Library/Developer/CoreSimulator/Caches").kind, .knownCache)
    }

    func testPackageManagerStoresOutsideTheOriginalListAreRecognised() {
        XCTAssertEqual(classify(".m2/repository").kind, .knownCache)
        XCTAssertEqual(classify(".nuget/packages").kind, .knownCache)
        XCTAssertEqual(classify("go/pkg/mod").kind, .knownCache)
        XCTAssertEqual(classify(".pub-cache").kind, .knownCache)
        XCTAssertEqual(classify(".bun/install/cache").kind, .knownCache)
    }

    /// An archive is the only copy of a shipped build. Calling it a cache would be
    /// wrong in the one direction that costs the user something irreplaceable.
    func testArchivesAreBuildOutputWithAnExplicitKeepWarningAndNotACache() {
        let evidence = classify("Library/Developer/Xcode/Archives")
        XCTAssertEqual(evidence.kind, .buildOutput)
        XCTAssertNotEqual(evidence.kind, .knownCache, "An archive must never be described as a regenerable cache.")
        XCTAssertTrue(evidence.detail.contains("products, not a cache"))
        XCTAssertTrue(evidence.rebuild?.contains("Keep any archive") ?? false)
    }

    func testDeviceLogsDoNotClaimToRegenerate() {
        let evidence = classify("Library/Developer/Xcode/iOS Device Logs")
        XCTAssertEqual(evidence.kind, .knownCache)
        XCTAssertTrue(evidence.rebuild?.contains("Not regenerated") ?? false, "Device logs are copied off a device, not rebuilt.")
    }

    /// Widening the catalogue must not widen what the app will act on.
    func testNewEntriesStillRespectTheSensitiveAndSourceGuards() {
        XCTAssertEqual(classify(".cache/../.ssh").kind, .sensitive)
        XCTAssertTrue(CleanupEvidenceKind.knownCache.supportsContentsReview)
        XCTAssertFalse(CleanupEvidenceKind.knownCache.isBlocked)
    }

    func testAnUnknownDeveloperPathStillReportsUnknownRatherThanGuessing() {
        XCTAssertEqual(classify("Library/Developer/Xcode/SomethingNobodyCatalogued").kind, .unknown)
    }
}
